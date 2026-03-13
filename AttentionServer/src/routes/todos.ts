import { FastifyInstance } from 'fastify';
import { v4 as uuidv4 } from 'uuid';
import { query } from '../config/database';
import { authenticate } from '../middleware/auth';
import { CreateTodoSchema, UpdateTodoSchema, PaginationSchema } from '../models/schemas';
import { pushChanges } from '../services/sync';

export async function todoRoutes(fastify: FastifyInstance): Promise<void> {
  fastify.addHook('onRequest', authenticate);

  // List todos with filtering and pagination
  fastify.get('/todos', async (request, reply) => {
    const pagination = PaginationSchema.parse(request.query);
    const qs = request.query as Record<string, string>;
    const offset = (pagination.page - 1) * pagination.limit;

    let whereClause = 'WHERE t.user_id = $1 AND t.deleted_at IS NULL';
    const params: unknown[] = [request.userId];
    let idx = 2;

    if (qs.status) {
      whereClause += ` AND t.status = $${idx++}`;
      params.push(qs.status);
    }
    if (qs.projectId) {
      whereClause += ` AND t.project_id = $${idx++}`;
      params.push(qs.projectId);
    }
    if (qs.areaId) {
      whereClause += ` AND t.area_id = $${idx++}`;
      params.push(qs.areaId);
    }
    if (qs.scheduledDate) {
      whereClause += ` AND DATE(t.scheduled_date) = $${idx++}`;
      params.push(qs.scheduledDate);
    }
    if (qs.tagId) {
      whereClause += ` AND EXISTS (SELECT 1 FROM todo_tags tt WHERE tt.todo_id = t.id AND tt.tag_id = $${idx++})`;
      params.push(qs.tagId);
    }

    params.push(pagination.limit, offset);

    const countResult = await query(
      `SELECT COUNT(*) FROM todos t ${whereClause}`,
      params.slice(0, idx - 1)
    );

    const result = await query(
      `SELECT t.*,
              COALESCE(
                json_agg(DISTINCT jsonb_build_object('id', tg.id, 'title', tg.title, 'color', tg.color))
                FILTER (WHERE tg.id IS NOT NULL), '[]'
              ) as tags,
              COALESCE(
                json_agg(DISTINCT jsonb_build_object('id', ci.id, 'title', ci.title, 'isCompleted', ci.is_completed, 'sortOrder', ci.sort_order))
                FILTER (WHERE ci.id IS NOT NULL), '[]'
              ) as checklist
       FROM todos t
       LEFT JOIN todo_tags tt ON tt.todo_id = t.id
       LEFT JOIN tags tg ON tg.id = tt.tag_id AND tg.deleted_at IS NULL
       LEFT JOIN checklist_items ci ON ci.todo_id = t.id AND ci.deleted_at IS NULL
       ${whereClause}
       GROUP BY t.id
       ORDER BY t.sort_order ASC, t.created_at DESC
       LIMIT $${idx++} OFFSET $${idx}`,
      params
    );

    return reply.send({
      data: result.rows.map(formatTodo),
      pagination: {
        page: pagination.page,
        limit: pagination.limit,
        total: parseInt(countResult.rows[0].count, 10),
      },
    });
  });

  // Get single todo
  fastify.get('/todos/:id', async (request, reply) => {
    const { id } = request.params as { id: string };

    const result = await query(
      `SELECT t.*,
              COALESCE(
                json_agg(DISTINCT jsonb_build_object('id', tg.id, 'title', tg.title, 'color', tg.color))
                FILTER (WHERE tg.id IS NOT NULL), '[]'
              ) as tags,
              COALESCE(
                json_agg(DISTINCT jsonb_build_object('id', ci.id, 'title', ci.title, 'isCompleted', ci.is_completed, 'sortOrder', ci.sort_order))
                FILTER (WHERE ci.id IS NOT NULL), '[]'
              ) as checklist,
              row_to_json(r) as recurrence
       FROM todos t
       LEFT JOIN todo_tags tt ON tt.todo_id = t.id
       LEFT JOIN tags tg ON tg.id = tt.tag_id AND tg.deleted_at IS NULL
       LEFT JOIN checklist_items ci ON ci.todo_id = t.id AND ci.deleted_at IS NULL
       LEFT JOIN recurrences r ON r.todo_id = t.id AND r.deleted_at IS NULL
       WHERE t.id = $1 AND t.user_id = $2 AND t.deleted_at IS NULL
       GROUP BY t.id, r.id`,
      [id, request.userId]
    );

    if (result.rows.length === 0) {
      return reply.status(404).send({ error: 'Todo not found' });
    }

    return reply.send(formatTodo(result.rows[0]));
  });

  // Create todo
  fastify.post('/todos', async (request, reply) => {
    const parsed = CreateTodoSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'Validation failed', details: parsed.error.issues });
    }

    const data = parsed.data;
    const todoId = data.id || uuidv4();

    await query(
      `INSERT INTO todos (id, user_id, title, notes, status, priority, scheduled_date, deadline, sort_order, heading_id, project_id, area_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)`,
      [todoId, request.userId, data.title, data.notes, data.status, data.priority,
       data.scheduledDate || null, data.deadline || null, data.sortOrder,
       data.headingId || null, data.projectId || null, data.areaId || null]
    );

    // Tags
    if (data.tagIds.length > 0) {
      const tagValues = data.tagIds.map((tagId, i) => `($1, $${i + 2})`).join(', ');
      const tagParams = [todoId, ...data.tagIds];
      await query(`INSERT INTO todo_tags (todo_id, tag_id) VALUES ${tagValues}`, tagParams);
    }

    // Checklist items
    for (const item of data.checklist) {
      const itemId = item.id || uuidv4();
      await query(
        `INSERT INTO checklist_items (id, user_id, todo_id, title, is_completed, sort_order)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [itemId, request.userId, todoId, item.title, item.isCompleted, item.sortOrder]
      );
    }

    // Recurrence
    if (data.recurrence) {
      const recId = data.recurrence.id || uuidv4();
      await query(
        `INSERT INTO recurrences (id, user_id, todo_id, frequency, interval, days_of_week, day_of_month, end_date)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
        [recId, request.userId, todoId, data.recurrence.frequency, data.recurrence.interval,
         data.recurrence.daysOfWeek || null, data.recurrence.dayOfMonth || null, data.recurrence.endDate || null]
      );
    }

    // Log sync
    await pushChanges(request.userId, [{
      entityType: 'todo',
      entityId: todoId,
      action: 'create',
      data: { ...data, id: todoId },
      version: 1,
    }]);

    return reply.status(201).send({ id: todoId, message: 'Todo created' });
  });

  // Update todo
  fastify.put('/todos/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const parsed = UpdateTodoSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'Validation failed', details: parsed.error.issues });
    }

    const data = parsed.data;

    // Check exists
    const existing = await query(
      'SELECT version FROM todos WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL',
      [id, request.userId]
    );
    if (existing.rows.length === 0) {
      return reply.status(404).send({ error: 'Todo not found' });
    }

    const newVersion = parseInt(existing.rows[0].version, 10) + 1;

    const setClauses: string[] = ['version = $1', 'updated_at = NOW()'];
    const params: unknown[] = [newVersion];
    let idx = 2;

    const fieldMap: Record<string, string> = {
      title: 'title', notes: 'notes', status: 'status', priority: 'priority',
      scheduledDate: 'scheduled_date', deadline: 'deadline', sortOrder: 'sort_order',
      headingId: 'heading_id', projectId: 'project_id', areaId: 'area_id',
    };

    for (const [field, column] of Object.entries(fieldMap)) {
      if (field in data) {
        setClauses.push(`${column} = $${idx++}`);
        params.push((data as Record<string, unknown>)[field] ?? null);
      }
    }

    // Handle completedAt based on status
    const statusValue = data.status as string | undefined;
    if (statusValue === 'completed') {
      setClauses.push(`completed_at = COALESCE(completed_at, NOW())`);
    } else if (statusValue && statusValue !== 'completed') {
      setClauses.push(`completed_at = NULL`);
    }

    params.push(id, request.userId);
    await query(
      `UPDATE todos SET ${setClauses.join(', ')} WHERE id = $${idx++} AND user_id = $${idx}`,
      params
    );

    // Update tags if provided
    if (data.tagIds !== undefined) {
      await query('DELETE FROM todo_tags WHERE todo_id = $1', [id]);
      if (data.tagIds.length > 0) {
        const tagValues = data.tagIds.map((_, i) => `($1, $${i + 2})`).join(', ');
        await query(`INSERT INTO todo_tags (todo_id, tag_id) VALUES ${tagValues}`, [id, ...data.tagIds]);
      }
    }

    // Update checklist if provided
    if (data.checklist !== undefined) {
      await query('UPDATE checklist_items SET deleted_at = NOW() WHERE todo_id = $1', [id]);
      for (const item of data.checklist) {
        const itemId = item.id || uuidv4();
        await query(
          `INSERT INTO checklist_items (id, user_id, todo_id, title, is_completed, sort_order)
           VALUES ($1, $2, $3, $4, $5, $6)
           ON CONFLICT (id) DO UPDATE SET title = $4, is_completed = $5, sort_order = $6, deleted_at = NULL, updated_at = NOW()`,
          [itemId, request.userId, id, item.title, item.isCompleted, item.sortOrder]
        );
      }
    }

    // Update recurrence if provided
    if (data.recurrence !== undefined) {
      await query('UPDATE recurrences SET deleted_at = NOW() WHERE todo_id = $1', [id]);
      if (data.recurrence) {
        const recId = data.recurrence.id || uuidv4();
        await query(
          `INSERT INTO recurrences (id, user_id, todo_id, frequency, interval, days_of_week, day_of_month, end_date)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
           ON CONFLICT (id) DO UPDATE SET frequency = $4, interval = $5, days_of_week = $6, day_of_month = $7, end_date = $8, deleted_at = NULL, updated_at = NOW()`,
          [recId, request.userId, id, data.recurrence.frequency, data.recurrence.interval,
           data.recurrence.daysOfWeek || null, data.recurrence.dayOfMonth || null, data.recurrence.endDate || null]
        );
      }
    }

    await pushChanges(request.userId, [{
      entityType: 'todo', entityId: id, action: 'update',
      data: data as Record<string, unknown>, version: newVersion,
    }]);

    return reply.send({ id, message: 'Todo updated', version: newVersion });
  });

  // Delete todo (soft delete)
  fastify.delete('/todos/:id', async (request, reply) => {
    const { id } = request.params as { id: string };

    const existing = await query(
      'SELECT version FROM todos WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL',
      [id, request.userId]
    );
    if (existing.rows.length === 0) {
      return reply.status(404).send({ error: 'Todo not found' });
    }

    const newVersion = parseInt(existing.rows[0].version, 10) + 1;

    await query(
      'UPDATE todos SET deleted_at = NOW(), version = $1, updated_at = NOW() WHERE id = $2 AND user_id = $3',
      [newVersion, id, request.userId]
    );

    await pushChanges(request.userId, [{
      entityType: 'todo', entityId: id, action: 'delete', version: newVersion,
    }]);

    return reply.send({ message: 'Todo deleted' });
  });
}

function formatTodo(row: Record<string, unknown>) {
  return {
    id: row.id,
    title: row.title,
    notes: row.notes,
    status: row.status,
    priority: row.priority,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    completedAt: row.completed_at,
    scheduledDate: row.scheduled_date,
    deadline: row.deadline,
    sortOrder: row.sort_order,
    headingId: row.heading_id,
    projectId: row.project_id,
    areaId: row.area_id,
    version: row.version,
    tags: row.tags,
    checklist: row.checklist,
    recurrence: row.recurrence || null,
  };
}
