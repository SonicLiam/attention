import fs from 'fs';
import path from 'path';
import { getPool, closePool } from './config/database';

async function migrate(): Promise<void> {
  const pool = getPool();
  const client = await pool.connect();

  try {
    // Create migrations tracking table
    await client.query(`
      CREATE TABLE IF NOT EXISTS _migrations (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) NOT NULL UNIQUE,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);

    // Get already applied migrations
    const applied = await client.query('SELECT name FROM _migrations ORDER BY id');
    const appliedNames = new Set(applied.rows.map(r => r.name));

    // Read migration files
    const migrationsDir = path.join(__dirname, '..', 'migrations');
    const files = fs.readdirSync(migrationsDir)
      .filter(f => f.endsWith('.sql'))
      .sort();

    for (const file of files) {
      if (appliedNames.has(file)) {
        console.log(`  Skipping ${file} (already applied)`);
        continue;
      }

      console.log(`  Applying ${file}...`);
      const sql = fs.readFileSync(path.join(migrationsDir, file), 'utf-8');
      await client.query(sql);
      await client.query('INSERT INTO _migrations (name) VALUES ($1)', [file]);
      console.log(`  Applied ${file}`);
    }

    console.log('All migrations applied successfully.');
  } catch (err) {
    console.error('Migration failed:', err);
    process.exit(1);
  } finally {
    client.release();
    await closePool();
  }
}

migrate();
