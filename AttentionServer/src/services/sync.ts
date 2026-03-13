import { query } from '../config/database';

export interface SyncChange {
  entityType: string;
  entityId: string;
  action: string;
  data?: Record<string, unknown>;
  version: number;
}

export interface SyncLogEntry {
  id: number;
  entityType: string;
  entityId: string;
  action: string;
  version: number;
  payload: Record<string, unknown> | null;
  createdAt: string;
}

/**
 * Write a batch of changes to the sync log.
 * Returns the new sync log entries with their IDs.
 */
export async function pushChanges(
  userId: string,
  changes: SyncChange[]
): Promise<SyncLogEntry[]> {
  const entries: SyncLogEntry[] = [];

  for (const change of changes) {
    const result = await query(
      `INSERT INTO sync_log (user_id, entity_type, entity_id, action, version, payload)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id, entity_type, entity_id, action, version, payload, created_at`,
      [userId, change.entityType, change.entityId, change.action, change.version, change.data ? JSON.stringify(change.data) : null]
    );

    const row = result.rows[0];
    entries.push({
      id: parseInt(row.id, 10),
      entityType: row.entity_type,
      entityId: row.entity_id,
      action: row.action,
      version: row.version,
      payload: row.payload,
      createdAt: row.created_at,
    });
  }

  return entries;
}

/**
 * Pull changes since a given sync log ID.
 * Returns all sync log entries after lastSyncId for the user.
 */
export async function pullChanges(
  userId: string,
  lastSyncId: number,
  limit: number = 500
): Promise<{ changes: SyncLogEntry[]; latestId: number }> {
  const result = await query(
    `SELECT id, entity_type, entity_id, action, version, payload, created_at
     FROM sync_log
     WHERE user_id = $1 AND id > $2
     ORDER BY id ASC
     LIMIT $3`,
    [userId, lastSyncId, limit]
  );

  const changes: SyncLogEntry[] = result.rows.map((row) => ({
    id: parseInt(row.id, 10),
    entityType: row.entity_type,
    entityId: row.entity_id,
    action: row.action,
    version: parseInt(row.version, 10),
    payload: row.payload,
    createdAt: row.created_at,
  }));

  const latestId = changes.length > 0 ? changes[changes.length - 1].id : lastSyncId;

  return { changes, latestId };
}

/**
 * Apply a single change to the database (last-writer-wins).
 * Only applies if the incoming version > current version.
 */
export async function applyChange(
  userId: string,
  change: SyncChange
): Promise<boolean> {
  const { entityType, entityId, action, data, version } = change;

  const tableName = getTableName(entityType);
  if (!tableName) return false;

  if (action === 'delete') {
    // Soft delete: set deleted_at, bump version
    const result = await query(
      `UPDATE ${tableName} SET deleted_at = NOW(), version = $1, updated_at = NOW()
       WHERE id = $2 AND user_id = $3 AND version < $1`,
      [version, entityId, userId]
    );
    return (result.rowCount ?? 0) > 0;
  }

  if (action === 'create') {
    // Upsert: insert or update if version is higher
    return await upsertEntity(tableName, userId, entityId, data || {}, version);
  }

  if (action === 'update') {
    if (!data) return false;
    return await updateEntity(tableName, userId, entityId, data, version);
  }

  return false;
}

function getTableName(entityType: string): string | null {
  const map: Record<string, string> = {
    todo: 'todos',
    project: 'projects',
    area: 'areas',
    tag: 'tags',
    checklist_item: 'checklist_items',
    recurrence: 'recurrences',
    heading: 'headings',
  };
  return map[entityType] || null;
}

async function upsertEntity(
  table: string,
  userId: string,
  entityId: string,
  data: Record<string, unknown>,
  version: number
): Promise<boolean> {
  // Check if entity exists
  const existing = await query(
    `SELECT version FROM ${table} WHERE id = $1 AND user_id = $2`,
    [entityId, userId]
  );

  if (existing.rows.length > 0) {
    const currentVersion = parseInt(existing.rows[0].version, 10);
    if (version <= currentVersion) return false;
    return await updateEntity(table, userId, entityId, data, version);
  }

  // Build insert from data
  const columns = ['id', 'user_id', 'version'];
  const values: unknown[] = [entityId, userId, version];
  const placeholders = ['$1', '$2', '$3'];
  let idx = 4;

  const columnMap = dataToColumns(data);
  for (const [col, val] of Object.entries(columnMap)) {
    columns.push(col);
    values.push(val);
    placeholders.push(`$${idx++}`);
  }

  await query(
    `INSERT INTO ${table} (${columns.join(', ')}) VALUES (${placeholders.join(', ')})
     ON CONFLICT (id) DO UPDATE SET version = EXCLUDED.version, updated_at = NOW()`,
    values
  );
  return true;
}

async function updateEntity(
  table: string,
  userId: string,
  entityId: string,
  data: Record<string, unknown>,
  version: number
): Promise<boolean> {
  const columnMap = dataToColumns(data);
  const setClauses: string[] = ['version = $1', 'updated_at = NOW()'];
  const values: unknown[] = [version];
  let idx = 2;

  for (const [col, val] of Object.entries(columnMap)) {
    setClauses.push(`${col} = $${idx++}`);
    values.push(val);
  }

  values.push(entityId, userId, version);

  const result = await query(
    `UPDATE ${table} SET ${setClauses.join(', ')}
     WHERE id = $${idx++} AND user_id = $${idx++} AND version < $${idx}`,
    values
  );

  return (result.rowCount ?? 0) > 0;
}

/**
 * Convert camelCase data keys to snake_case column names.
 */
function dataToColumns(data: Record<string, unknown>): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  const keyMap: Record<string, string> = {
    title: 'title',
    notes: 'notes',
    status: 'status',
    priority: 'priority',
    completedAt: 'completed_at',
    scheduledDate: 'scheduled_date',
    deadline: 'deadline',
    sortOrder: 'sort_order',
    headingId: 'heading_id',
    projectId: 'project_id',
    areaId: 'area_id',
    parentTagId: 'parent_tag_id',
    color: 'color',
    isCompleted: 'is_completed',
    todoId: 'todo_id',
    frequency: 'frequency',
    interval: 'interval',
    daysOfWeek: 'days_of_week',
    dayOfMonth: 'day_of_month',
    endDate: 'end_date',
    displayName: 'display_name',
  };

  for (const [key, value] of Object.entries(data)) {
    const col = keyMap[key];
    if (col) {
      result[col] = value;
    }
  }

  return result;
}
