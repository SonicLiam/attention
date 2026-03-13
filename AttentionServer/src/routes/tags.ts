import { FastifyInstance } from 'fastify';
import { v4 as uuidv4 } from 'uuid';
import { query } from '../config/database';
import { authenticate } from '../middleware/auth';
import { CreateTagSchema, UpdateTagSchema } from '../models/schemas';
import { pushChanges } from '../services/sync';

export async function tagRoutes(fastify: FastifyInstance): Promise<void> {
  fastify.addHook('onRequest', authenticate);

  // List tags
  fastify.get('/tags', async (request, reply) => {
    const result = await query(
      `SELECT t.*,
              (SELECT COUNT(*) FROM todo_tags tt
               JOIN todos td ON td.id = tt.todo_id AND td.deleted_at IS NULL
               WHERE tt.tag_id = t.id) as todo_count
       FROM tags t
       WHERE t.user_id = $1 AND t.deleted_at IS NULL
       ORDER BY t.sort_order ASC, t.created_at ASC`,
      [request.userId]
    );

    return reply.send({ data: result.rows.map(formatTag) });
  });

  // Get single tag
  fastify.get('/tags/:id', async (request, reply) => {
    const { id } = request.params as { id: string };

    const result = await query(
      `SELECT t.*,
              (SELECT COUNT(*) FROM todo_tags tt
               JOIN todos td ON td.id = tt.todo_id AND td.deleted_at IS NULL
               WHERE tt.tag_id = t.id) as todo_count
       FROM tags t
       WHERE t.id = $1 AND t.user_id = $2 AND t.deleted_at IS NULL`,
      [id, request.userId]
    );

    if (result.rows.length === 0) {
      return reply.status(404).send({ error: 'Tag not found' });
    }

    return reply.send(formatTag(result.rows[0]));
  });

  // Create tag
  fastify.post('/tags', async (request, reply) => {
    const parsed = CreateTagSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'Validation failed', details: parsed.error.issues });
    }

    const data = parsed.data;
    const tagId = data.id || uuidv4();

    await query(
      `INSERT INTO tags (id, user_id, title, color, sort_order, parent_tag_id)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [tagId, request.userId, data.title, data.color, data.sortOrder, data.parentTagId || null]
    );

    await pushChanges(request.userId, [{
      entityType: 'tag', entityId: tagId, action: 'create',
      data: { ...data, id: tagId }, version: 1,
    }]);

    return reply.status(201).send({ id: tagId, message: 'Tag created' });
  });

  // Update tag
  fastify.put('/tags/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const parsed = UpdateTagSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'Validation failed', details: parsed.error.issues });
    }

    const data = parsed.data;

    const existing = await query(
      'SELECT version FROM tags WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL',
      [id, request.userId]
    );
    if (existing.rows.length === 0) {
      return reply.status(404).send({ error: 'Tag not found' });
    }

    const newVersion = parseInt(existing.rows[0].version, 10) + 1;

    const setClauses: string[] = ['version = $1', 'updated_at = NOW()'];
    const params: unknown[] = [newVersion];
    let idx = 2;

    const fieldMap: Record<string, string> = {
      title: 'title', color: 'color', sortOrder: 'sort_order', parentTagId: 'parent_tag_id',
    };

    for (const [field, column] of Object.entries(fieldMap)) {
      if (field in data) {
        setClauses.push(`${column} = $${idx++}`);
        params.push((data as Record<string, unknown>)[field] ?? null);
      }
    }

    params.push(id, request.userId);
    await query(
      `UPDATE tags SET ${setClauses.join(', ')} WHERE id = $${idx++} AND user_id = $${idx}`,
      params
    );

    await pushChanges(request.userId, [{
      entityType: 'tag', entityId: id, action: 'update',
      data: data as Record<string, unknown>, version: newVersion,
    }]);

    return reply.send({ id, message: 'Tag updated', version: newVersion });
  });

  // Delete tag
  fastify.delete('/tags/:id', async (request, reply) => {
    const { id } = request.params as { id: string };

    const existing = await query(
      'SELECT version FROM tags WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL',
      [id, request.userId]
    );
    if (existing.rows.length === 0) {
      return reply.status(404).send({ error: 'Tag not found' });
    }

    const newVersion = parseInt(existing.rows[0].version, 10) + 1;

    await query(
      'UPDATE tags SET deleted_at = NOW(), version = $1, updated_at = NOW() WHERE id = $2 AND user_id = $3',
      [newVersion, id, request.userId]
    );

    // Remove tag associations
    await query('DELETE FROM todo_tags WHERE tag_id = $1', [id]);

    // Unlink child tags
    await query('UPDATE tags SET parent_tag_id = NULL, updated_at = NOW() WHERE parent_tag_id = $1', [id]);

    await pushChanges(request.userId, [{
      entityType: 'tag', entityId: id, action: 'delete', version: newVersion,
    }]);

    return reply.send({ message: 'Tag deleted' });
  });
}

function formatTag(row: Record<string, unknown>) {
  return {
    id: row.id,
    title: row.title,
    color: row.color,
    sortOrder: row.sort_order,
    parentTagId: row.parent_tag_id,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    version: row.version,
    todoCount: parseInt(row.todo_count as string, 10) || 0,
  };
}
