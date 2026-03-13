import { FastifyInstance } from 'fastify';
import type { WebSocket } from 'ws';
import { getRedis } from '../config/redis';
import { pullChanges, pushChanges, applyChange, SyncChange } from '../services/sync';
import { SyncPushSchema } from '../models/schemas';

interface AuthenticatedSocket {
  socket: WebSocket;
  userId: string;
  deviceId: string;
}

// Track connected clients per user
const connectedClients = new Map<string, Set<AuthenticatedSocket>>();

export async function websocketSync(fastify: FastifyInstance): Promise<void> {
  fastify.get('/ws/sync', { websocket: true }, async (socket, request) => {
    let userId: string | null = null;
    let deviceId: string = 'unknown';

    // Authenticate via token query param or first message
    const url = new URL(request.url, `http://${request.headers.host}`);
    const token = url.searchParams.get('token');
    deviceId = url.searchParams.get('deviceId') || 'unknown';

    if (token) {
      try {
        const decoded = fastify.jwt.verify<{ userId: string; email: string }>(token);
        userId = decoded.userId;
      } catch {
        socket.send(JSON.stringify({ type: 'error', message: 'Authentication failed' }));
        socket.close(4001, 'Unauthorized');
        return;
      }
    }

    if (!userId) {
      socket.send(JSON.stringify({ type: 'auth_required', message: 'Send auth token' }));

      // Wait for auth message
      const authTimeout = setTimeout(() => {
        socket.close(4001, 'Auth timeout');
      }, 10000);

      socket.once('message', async (rawData) => {
        clearTimeout(authTimeout);
        try {
          const msg = JSON.parse(rawData.toString());
          if (msg.type === 'auth' && msg.token) {
            const decoded = fastify.jwt.verify<{ userId: string; email: string }>(msg.token);
            userId = decoded.userId;
            deviceId = msg.deviceId || deviceId;
            registerClient(socket, userId, deviceId);
            socket.send(JSON.stringify({ type: 'auth_success' }));
            setupMessageHandler(socket, userId, deviceId, fastify);
          } else {
            socket.close(4001, 'Invalid auth message');
          }
        } catch {
          socket.close(4001, 'Authentication failed');
        }
      });
    } else {
      registerClient(socket, userId, deviceId);
      socket.send(JSON.stringify({ type: 'auth_success' }));
      setupMessageHandler(socket, userId, deviceId, fastify);
    }

    socket.on('close', () => {
      if (userId) {
        unregisterClient(socket, userId);
      }
    });

    socket.on('error', () => {
      if (userId) {
        unregisterClient(socket, userId);
      }
    });
  });
}

function registerClient(socket: WebSocket, userId: string, deviceId: string): void {
  if (!connectedClients.has(userId)) {
    connectedClients.set(userId, new Set());
  }
  connectedClients.get(userId)!.add({ socket, userId, deviceId });
}

function unregisterClient(socket: WebSocket, userId: string): void {
  const clients = connectedClients.get(userId);
  if (clients) {
    for (const client of clients) {
      if (client.socket === socket) {
        clients.delete(client);
        break;
      }
    }
    if (clients.size === 0) {
      connectedClients.delete(userId);
    }
  }
}

function setupMessageHandler(
  socket: WebSocket,
  userId: string,
  deviceId: string,
  _fastify: FastifyInstance
): void {
  socket.on('message', async (rawData) => {
    try {
      const msg = JSON.parse(rawData.toString());

      switch (msg.type) {
        case 'push': {
          // Client pushes changes to server
          const parsed = SyncPushSchema.safeParse(msg);
          if (!parsed.success) {
            socket.send(JSON.stringify({
              type: 'error',
              message: 'Invalid push data',
              details: parsed.error.issues,
            }));
            return;
          }

          // Apply each change (last-writer-wins)
          for (const change of parsed.data.changes) {
            await applyChange(userId, change as SyncChange);
          }

          // Log to sync_log
          const entries = await pushChanges(userId, parsed.data.changes as SyncChange[]);

          // Acknowledge
          socket.send(JSON.stringify({
            type: 'push_ack',
            syncedIds: entries.map(e => e.id),
            latestSyncId: entries.length > 0 ? entries[entries.length - 1].id : 0,
          }));

          // Broadcast to other devices of the same user
          broadcastToOtherDevices(userId, deviceId, {
            type: 'changes',
            changes: entries,
          });

          // Also publish to Redis for multi-instance support
          try {
            const redis = getRedis();
            await redis.publish(`sync:${userId}`, JSON.stringify({
              type: 'changes',
              changes: entries,
              sourceDeviceId: deviceId,
            }));
          } catch {
            // Redis publish failure is non-fatal
          }

          break;
        }

        case 'pull': {
          // Client requests changes since lastSyncId
          const lastSyncId = parseInt(msg.lastSyncId, 10) || 0;
          const result = await pullChanges(userId, lastSyncId);

          socket.send(JSON.stringify({
            type: 'pull_response',
            changes: result.changes,
            latestSyncId: result.latestId,
          }));
          break;
        }

        case 'ping': {
          socket.send(JSON.stringify({ type: 'pong', timestamp: Date.now() }));
          break;
        }

        default: {
          socket.send(JSON.stringify({ type: 'error', message: `Unknown message type: ${msg.type}` }));
        }
      }
    } catch (err) {
      socket.send(JSON.stringify({
        type: 'error',
        message: 'Failed to process message',
      }));
    }
  });
}

function broadcastToOtherDevices(
  userId: string,
  sourceDeviceId: string,
  message: Record<string, unknown>
): void {
  const clients = connectedClients.get(userId);
  if (!clients) return;

  const payload = JSON.stringify(message);
  for (const client of clients) {
    if (client.deviceId !== sourceDeviceId && client.socket.readyState === 1 /* OPEN */) {
      client.socket.send(payload);
    }
  }
}
