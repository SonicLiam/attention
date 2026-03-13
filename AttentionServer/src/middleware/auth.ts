import { FastifyRequest, FastifyReply } from 'fastify';

export interface JWTPayload {
  userId: string;
  email: string;
}

declare module 'fastify' {
  interface FastifyRequest {
    userId: string;
  }
}

declare module '@fastify/jwt' {
  interface FastifyJWT {
    payload: JWTPayload;
    user: JWTPayload;
  }
}

export async function authenticate(request: FastifyRequest, reply: FastifyReply): Promise<void> {
  try {
    await request.jwtVerify();
    request.userId = request.user.userId;
  } catch (err) {
    reply.status(401).send({ error: 'Unauthorized', message: 'Invalid or expired token' });
  }
}
