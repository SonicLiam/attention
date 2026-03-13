import { FastifyInstance } from 'fastify';
import { v4 as uuidv4 } from 'uuid';
import { query } from '../config/database';
import { authenticate } from '../middleware/auth';
import { CreateProjectSchema, UpdateProjectSchema, PaginationSchema } from '../models/schemas';
import { pushChanges } from '../services/sync';

export async function projectRoutes(fastify: FastifyInstance): Promise<void> {
  fastify.addHook('onRequest', authenticate);

  // List projects
  fastify.get('/projects', async (request, reply) => {
    const pagination = PaginationSchema.parse(request.query);
    const qs = request.query as Record<string, string>;
    const offset = (pagination.page - 1) * pagination.limit;

    let whereClause = 'WHERE p.user_id = $1 AND p.deleted_at IS NULL';
    const params: unknown[] = [request.userId];
    let idx = 2;

    if (qs.status) {
      whereClause += ` AND p.status = $${idx++}`;
      params.push(qs.status);
    }
    if (qs.areaId) {
      whereClause += ` AND p.area_id = $${idx++}`;
      params.push(qs.areaId);
    }

    params.push(pagination.limit, offset);

    const countResult = await query(
      `SELECT COUNT(*) FROM projects p ${whereClause}`,
      params.slice(0, idx - 1)
    );

    const result = await query(
      `SELECT p.*,
              (SELECT COUNT(*) FROM todos WHERE project_id = p.id AND deleted_at IS NULL) as total_todos,
              (SELECT COUNT(*) FROM todos WHERE project_id = p.id AND status = 'completed' AND deleted_at IS NULL) as completed_todos,
              COALESCE(
                json_agg(DISTINCT jsonb_build_object('id', h.id, 'title', h.title, 'sortOrder', h.sort_order))
                FILTER (WHERE h.id IS NOT NULL), '[]'
              ) as headings
       FROM projects p
       LEFT JOIN headings h ON h.project_id = p.id AND h.deleted_at IS NULL
       ${whereClause}
       GROUP BY p.id
       ORDER BY p.sort_order ASC, p.created_at DESC
       LIMIT $${idx++} OFFSET $${idx}`,
      params
    );

    return reply.send({
      data: result.rows.map(formatProject),
      pagination: {
        page: pagination.page,
        limit: pagination.limit,
        total: parseInt(countResult.rows[0].count, 10),
      },
    });
  });

  // Get single project
  fastify.get('/projects/:id', async (request, reply) => {
    const { id } = request.params as { id: string };

    const result = await query(
      `SELECT p.*,
              (SELECT COUNT(*) FROM todos WHERE project_id = p.id AND deleted_at IS NULL) as total_todos,
              (SELECT COUNT(*) FROM todos WHERE project_id = p.id AND status = 'completed' AND deleted_at IS NULL) as completed_todos,
              COALESCE(
                json_agg(DISTINCT jsonb_build_object('id', h.id, 'title', h.title, 'sortOrder', h.sort_order))
                FILTER (WHERE h.id IS NOT NULL), '[]'
              ) as headings
       FROM projects p
       LEFT JOIN headings h ON h.project_id = p.id AND h.deleted_at IS NULL
       WHERE p.id = $1 AND p.user_id = $2 AND p.deleted_at IS NULL
       GROUP BY p.id`,
      [id, request.userId]
    );

    if (result.rows.length === 0) {
      return reply.status(404).send({ error: 'Project not found' });
    }

    return reply.send(formatProject(result.rows[0]));
  });

  // Create project
  fastify.post('/projects', async (request, reply) => {
    const parsed = CreateProjectSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'Validation failed', details: parsed.error.issues });
    }

    const data = parsed.data;
    const projectId = data.id || uuidv4();

    await query(
      `INSERT INTO projects (id, user_id, title, notes, status, deadline, sort_order, area_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [projectId, request.userId, data.title, data.notes, data.status,
       data.deadline || null, data.sortOrder, data.areaId || null]
    );

    for (const heading of data.headings) {
      const headingId = heading.id || uuidv4();
      await query(
        `INSERT INTO headings (id, user_id, title, sort_order, project_id)
         VALUES ($1, $2, $3, $4, $5)`,
        [headingId, request.userId, heading.title, heading.sortOrder, projectId]
      );
    }

    await pushChanges(request.userId, [{
      entityType: 'project', entityId: projectId, action: 'create',
      data: { ...data, id: projectId }, version: 1,
    }]);

    return reply.status(201).send({ id: projectId, message: 'Project created' });
  });

  // Update project
  fastify.put('/projects/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const parsed = UpdateProjectSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'Validation failed', details: parsed.error.issues });
    }

    const data = parsed.data;

    const existing = await query(
      'SELECT version FROM projects WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL',
      [id, request.userId]
    );
    if (existing.rows.length === 0) {
      return reply.status(404).send({ error: 'Project not found' });
    }

    const newVersion = parseInt(existing.rows[0].version, 10) + 1;

    const setClauses: string[] = ['version = $1', 'updated_at = NOW()'];
    const params: unknown[] = [newVersion];
    let idx = 2;

    const fieldMap: Record<string, string> = {
      title: 'title', notes: 'notes', status: 'status',
      deadline: 'deadline', sortOrder: 'sort_order', areaId: 'area_id',
    };

    for (const [field, column] of Object.entries(fieldMap)) {
      if (field in data) {
        setClauses.push(`${column} = $${idx++}`);
        params.push((data as Record<string, unknown>)[field] ?? null);
      }
    }

    params.push(id, request.userId);
    await query(
      `UPDATE projects SET ${setClauses.join(', ')} WHERE id = $${idx++} AND user_id = $${idx}`,
      params
    );

    // Update headings if provided
    if (data.headings !== undefined) {
      await query('UPDATE headings SET deleted_at = NOW() WHERE project_id = $1', [id]);
      for (const heading of data.headings) {
        const headingId = heading.id || uuidv4();
        await query(
          `INSERT INTO headings (id, user_id, title, sort_order, project_id)
           VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (id) DO UPDATE SET title = $3, sort_order = $4, deleted_at = NULL, updated_at = NOW()`,
          [headingId, request.userId, heading.title, heading.sortOrder, id]
        );
      }
    }

    await pushChanges(request.userId, [{
      entityType: 'project', entityId: id, action: 'update',
      data: data as Record<string, unknown>, version: newVersion,
    }]);

    return reply.send({ id, message: 'Project updated', version: newVersion });
  });

  // Delete project
  fastify.delete('/projects/:id', async (request, reply) => {
    const { id } = request.params as { id: string };

    const existing = await query(
      'SELECT version FROM projects WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL',
      [id, request.userId]
    );
    if (existing.rows.length === 0) {
      return reply.status(404).send({ error: 'Project not found' });
    }

    const newVersion = parseInt(existing.rows[0].version, 10) + 1;

    await query(
      'UPDATE projects SET deleted_at = NOW(), version = $1, updated_at = NOW() WHERE id = $2 AND user_id = $3',
      [newVersion, id, request.userId]
    );

    await pushChanges(request.userId, [{
      entityType: 'project', entityId: id, action: 'delete', version: newVersion,
    }]);

    return reply.send({ message: 'Project deleted' });
  });
}

function formatProject(row: Record<string, unknown>) {
  return {
    id: row.id,
    title: row.title,
    notes: row.notes,
    status: row.status,
    deadline: row.deadline,
    sortOrder: row.sort_order,
    areaId: row.area_id,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    version: row.version,
    totalTodos: parseInt(row.total_todos as string, 10) || 0,
    completedTodos: parseInt(row.completed_todos as string, 10) || 0,
    headings: row.headings,
  };
}
