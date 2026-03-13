import Fastify from 'fastify';
import fastifyJwt from '@fastify/jwt';
import fastifyCors from '@fastify/cors';
import fastifyWebsocket from '@fastify/websocket';
import { config } from './config/env';
import { getRedis, closeRedis } from './config/redis';
import { closePool } from './config/database';
import { authRoutes } from './routes/auth';
import { todoRoutes } from './routes/todos';
import { projectRoutes } from './routes/projects';
import { areaRoutes } from './routes/areas';
import { tagRoutes } from './routes/tags';
import { websocketSync } from './websocket/sync';

async function main(): Promise<void> {
  const fastify = Fastify({
    logger: {
      level: config.nodeEnv === 'production' ? 'info' : 'debug',
    },
  });

  // Plugins
  await fastify.register(fastifyCors, {
    origin: true,
    credentials: true,
  });

  await fastify.register(fastifyJwt, {
    secret: config.jwt.secret,
  });

  await fastify.register(fastifyWebsocket);

  // Health check
  fastify.get('/health', async () => {
    return { status: 'ok', timestamp: new Date().toISOString() };
  });

  // Routes
  await fastify.register(authRoutes, { prefix: '/api/v1' });
  await fastify.register(todoRoutes, { prefix: '/api/v1' });
  await fastify.register(projectRoutes, { prefix: '/api/v1' });
  await fastify.register(areaRoutes, { prefix: '/api/v1' });
  await fastify.register(tagRoutes, { prefix: '/api/v1' });

  // WebSocket
  await fastify.register(websocketSync);

  // Connect Redis
  try {
    const redis = getRedis();
    await redis.connect();
    fastify.log.info('Redis connected');
  } catch (err) {
    fastify.log.warn('Redis connection failed, continuing without Redis: %s', err);
  }

  // Graceful shutdown
  const shutdown = async () => {
    fastify.log.info('Shutting down...');
    await fastify.close();
    await closeRedis();
    await closePool();
    process.exit(0);
  };

  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);

  // Start
  try {
    await fastify.listen({ port: config.port, host: config.host });
    fastify.log.info(`Server running at http://${config.host}:${config.port}`);
  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }
}

main();
