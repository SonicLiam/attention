import { FastifyInstance } from 'fastify';
import { v4 as uuidv4 } from 'uuid';
import { query } from '../config/database';
import { authenticate } from '../middleware/auth';
import { CreateAreaSchema, UpdateAreaSchema } from '../models/schemas';
import { pushChanges } from '../services/sync';

export async function areaRoutes(fastify: FastifyInstance): Promise<void> {
  fastify.addHook('onRequest', authenticate);

  // List areas
  fastify.get('/areas', async (request, reply) => {
    const result = await query(
      `SELECT a.*,
              (SELECT COUNT(*) FROM projects WHERE area_id = a.id AND deleted_at IS NULL) as project_count,
              (SELECT COUNT(*) FROM todos WHERE area_id = a.id AND project_id IS NULL AND deleted_at IS NULL) as todo_count
       FROM areas a
       WHERE a.user_id = $1 AND a.deleted_at IS NULL
       ORDER BY a.sort_order ASC, a.created_at ASC`,
      [request.userId]
    );

    return reply.send({ data: result.rows.map(formatArea) });
  });

  // Get single area
  fastify.get('/areas/:id', async (request, reply) => {
    const { id } = request.params as { id: string };

    const result = await query(
      `SELECT a.*,
              (SELECT COUNT(*) FROM projects WHERE area_id = a.id AND deleted_at IS NULL) as project_count,
              (SELECT COUNT(*) FROM todos WHERE area_id = a.id AND project_id IS NULL AND deleted_at IS NULL) as todo_count
       FROM areas a
       WHERE a.id = $1 AND a.user_id = $2 AND a.deleted_at IS NULL`,
      [id, request.userId]
    );

    if (result.rows.length === 0) {
      return reply.status(404).send({ error: 'Area not found' });
    }

    return reply.send(formatArea(result.rows[0]));
  });

  // Create area
  fastify.post('/areas', async (request, reply) => {
    const parsed = CreateAreaSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'Validation failed', details: parsed.error.issues });
    }

    const data = parsed.data;
    const areaId = data.id || uuidv4();

    await query(
      `INSERT INTO areas (id, user_id, title, sort_order)
       VALUES ($1, $2, $3, $4)`,
      [areaId, request.userId, data.title, data.sortOrder]
    );

    await pushChanges(request.userId, [{
      entityType: 'area', entityId: areaId, action: 'create',
      data: { ...data, id: areaId }, version: 1,
    }]);

    return reply.status(201).send({ id: areaId, message: 'Area created' });
  });

  // Update area
  fastify.put('/areas/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const parsed = UpdateAreaSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'Validation failed', details: parsed.error.issues });
    }

    const data = parsed.data;

    const existing = await query(
      'SELECT version FROM areas WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL',
      [id, request.userId]
    );
    if (existing.rows.length === 0) {
      return reply.status(404).send({ error: 'Area not found' });
    }

    const newVersion = parseInt(existing.rows[0].version, 10) + 1;

    const setClauses: string[] = ['version = $1', 'updated_at = NOW()'];
    const params: unknown[] = [newVersion];
    let idx = 2;

    if (data.title !== undefined) {
      setClauses.push(`title = $${idx++}`);
      params.push(data.title);
    }
    if (data.sortOrder !== undefined) {
      setClauses.push(`sort_order = $${idx++}`);
      params.push(data.sortOrder);
    }

    params.push(id, request.userId);
    await query(
      `UPDATE areas SET ${setClauses.join(', ')} WHERE id = $${idx++} AND user_id = $${idx}`,
      params
    );

    await pushChanges(request.userId, [{
      entityType: 'area', entityId: id, action: 'update',
      data: data as Record<string, unknown>, version: newVersion,
    }]);

    return reply.send({ id, message: 'Area updated', version: newVersion });
  });

  // Delete area
  fastify.delete('/areas/:id', async (request, reply) => {
    const { id } = request.params as { id: string };

    const existing = await query(
      'SELECT version FROM areas WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL',
      [id, request.userId]
    );
    if (existing.rows.length === 0) {
      return reply.status(404).send({ error: 'Area not found' });
    }

    const newVersion = parseInt(existing.rows[0].version, 10) + 1;

    await query(
      'UPDATE areas SET deleted_at = NOW(), version = $1, updated_at = NOW() WHERE id = $2 AND user_id = $3',
      [newVersion, id, request.userId]
    );

    // Unlink projects and todos
    await query('UPDATE projects SET area_id = NULL, updated_at = NOW() WHERE area_id = $1', [id]);
    await query('UPDATE todos SET area_id = NULL, updated_at = NOW() WHERE area_id = $1', [id]);

    await pushChanges(request.userId, [{
      entityType: 'area', entityId: id, action: 'delete', version: newVersion,
    }]);

    return reply.send({ message: 'Area deleted' });
  });
}

function formatArea(row: Record<string, unknown>) {
  return {
    id: row.id,
    title: row.title,
    sortOrder: row.sort_order,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    version: row.version,
    projectCount: parseInt(row.project_count as string, 10) || 0,
    todoCount: parseInt(row.todo_count as string, 10) || 0,
  };
}
