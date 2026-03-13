import { FastifyInstance } from 'fastify';
import bcrypt from 'bcryptjs';
import { v4 as uuidv4 } from 'uuid';
import crypto from 'crypto';
import { query } from '../config/database';
import { RegisterSchema, LoginSchema, RefreshSchema } from '../models/schemas';
import { config } from '../config/env';

function hashToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}

export async function authRoutes(fastify: FastifyInstance): Promise<void> {
  // Register
  fastify.post('/auth/register', async (request, reply) => {
    const parsed = RegisterSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'Validation failed', details: parsed.error.issues });
    }

    const { email, password, displayName } = parsed.data;

    // Check if user exists
    const existing = await query('SELECT id FROM users WHERE email = $1', [email]);
    if (existing.rows.length > 0) {
      return reply.status(409).send({ error: 'Email already registered' });
    }

    const passwordHash = await bcrypt.hash(password, 12);
    const userId = uuidv4();

    await query(
      'INSERT INTO users (id, email, password_hash, display_name) VALUES ($1, $2, $3, $4)',
      [userId, email, passwordHash, displayName || null]
    );

    const accessToken = fastify.jwt.sign(
      { userId, email },
      { expiresIn: config.jwt.expiresIn }
    );

    const refreshToken = uuidv4();
    const refreshExpires = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

    await query(
      'INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)',
      [userId, hashToken(refreshToken), refreshExpires]
    );

    return reply.status(201).send({
      user: { id: userId, email, displayName: displayName || null },
      accessToken,
      refreshToken,
    });
  });

  // Login
  fastify.post('/auth/login', async (request, reply) => {
    const parsed = LoginSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'Validation failed', details: parsed.error.issues });
    }

    const { email, password } = parsed.data;

    const result = await query(
      'SELECT id, email, password_hash, display_name FROM users WHERE email = $1',
      [email]
    );

    if (result.rows.length === 0) {
      return reply.status(401).send({ error: 'Invalid email or password' });
    }

    const user = result.rows[0];
    const valid = await bcrypt.compare(password, user.password_hash);
    if (!valid) {
      return reply.status(401).send({ error: 'Invalid email or password' });
    }

    const accessToken = fastify.jwt.sign(
      { userId: user.id, email: user.email },
      { expiresIn: config.jwt.expiresIn }
    );

    const refreshToken = uuidv4();
    const refreshExpires = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

    await query(
      'INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)',
      [user.id, hashToken(refreshToken), refreshExpires]
    );

    return reply.send({
      user: { id: user.id, email: user.email, displayName: user.display_name },
      accessToken,
      refreshToken,
    });
  });

  // Refresh token
  fastify.post('/auth/refresh', async (request, reply) => {
    const parsed = RefreshSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'Validation failed' });
    }

    const { refreshToken } = parsed.data;
    const tokenHash = hashToken(refreshToken);

    const result = await query(
      `SELECT rt.id, rt.user_id, u.email, u.display_name
       FROM refresh_tokens rt
       JOIN users u ON u.id = rt.user_id
       WHERE rt.token_hash = $1 AND rt.expires_at > NOW()`,
      [tokenHash]
    );

    if (result.rows.length === 0) {
      return reply.status(401).send({ error: 'Invalid or expired refresh token' });
    }

    const row = result.rows[0];

    // Rotate: delete old, create new
    await query('DELETE FROM refresh_tokens WHERE id = $1', [row.id]);

    const accessToken = fastify.jwt.sign(
      { userId: row.user_id, email: row.email },
      { expiresIn: config.jwt.expiresIn }
    );

    const newRefreshToken = uuidv4();
    const refreshExpires = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

    await query(
      'INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)',
      [row.user_id, hashToken(newRefreshToken), refreshExpires]
    );

    return reply.send({
      user: { id: row.user_id, email: row.email, displayName: row.display_name },
      accessToken,
      refreshToken: newRefreshToken,
    });
  });
}
