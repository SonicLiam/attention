import { z } from 'zod';

// Enums matching Swift models
export const TodoStatus = z.enum(['inbox', 'active', 'completed', 'cancelled']);
export const ProjectStatus = z.enum(['active', 'completed', 'cancelled']);
export const Priority = z.number().int().min(0).max(3);
export const RecurrenceFrequency = z.enum(['daily', 'weekly', 'biweekly', 'monthly', 'yearly', 'custom']);

// Auth schemas
export const RegisterSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8).max(128),
  displayName: z.string().min(1).max(255).optional(),
});

export const LoginSchema = z.object({
  email: z.string().email(),
  password: z.string(),
});

export const RefreshSchema = z.object({
  refreshToken: z.string(),
});

// Todo schemas
export const CreateTodoSchema = z.object({
  id: z.string().uuid().optional(),
  title: z.string().min(1).max(500),
  notes: z.string().default(''),
  status: TodoStatus.default('inbox'),
  priority: Priority.default(0),
  scheduledDate: z.string().datetime().nullable().optional(),
  deadline: z.string().datetime().nullable().optional(),
  sortOrder: z.number().int().default(0),
  headingId: z.string().uuid().nullable().optional(),
  projectId: z.string().uuid().nullable().optional(),
  areaId: z.string().uuid().nullable().optional(),
  tagIds: z.array(z.string().uuid()).default([]),
  checklist: z.array(z.object({
    id: z.string().uuid().optional(),
    title: z.string().min(1).max(500),
    isCompleted: z.boolean().default(false),
    sortOrder: z.number().int().default(0),
  })).default([]),
  recurrence: z.object({
    id: z.string().uuid().optional(),
    frequency: RecurrenceFrequency,
    interval: z.number().int().min(1).default(1),
    daysOfWeek: z.array(z.number().int().min(1).max(7)).nullable().optional(),
    dayOfMonth: z.number().int().min(1).max(31).nullable().optional(),
    endDate: z.string().datetime().nullable().optional(),
  }).nullable().optional(),
});

export const UpdateTodoSchema = CreateTodoSchema.partial().omit({ id: true });

// Project schemas
export const CreateProjectSchema = z.object({
  id: z.string().uuid().optional(),
  title: z.string().min(1).max(255),
  notes: z.string().default(''),
  status: ProjectStatus.default('active'),
  deadline: z.string().datetime().nullable().optional(),
  sortOrder: z.number().int().default(0),
  areaId: z.string().uuid().nullable().optional(),
  headings: z.array(z.object({
    id: z.string().uuid().optional(),
    title: z.string().min(1).max(255),
    sortOrder: z.number().int().default(0),
  })).default([]),
});

export const UpdateProjectSchema = CreateProjectSchema.partial().omit({ id: true });

// Area schemas
export const CreateAreaSchema = z.object({
  id: z.string().uuid().optional(),
  title: z.string().min(1).max(255),
  sortOrder: z.number().int().default(0),
});

export const UpdateAreaSchema = CreateAreaSchema.partial().omit({ id: true });

// Tag schemas
export const CreateTagSchema = z.object({
  id: z.string().uuid().optional(),
  title: z.string().min(1).max(255),
  color: z.string().default('#6366F1'),
  sortOrder: z.number().int().default(0),
  parentTagId: z.string().uuid().nullable().optional(),
});

export const UpdateTagSchema = CreateTagSchema.partial().omit({ id: true });

// Pagination
export const PaginationSchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(50),
});

// Sync schemas
export const SyncPushSchema = z.object({
  changes: z.array(z.object({
    entityType: z.enum(['todo', 'project', 'area', 'tag', 'checklist_item', 'recurrence', 'heading']),
    entityId: z.string().uuid(),
    action: z.enum(['create', 'update', 'delete']),
    data: z.record(z.unknown()).optional(),
    version: z.number().int(),
  })),
  lastSyncId: z.number().int().optional(),
});

export const SyncPullSchema = z.object({
  lastSyncId: z.number().int().default(0),
});

// Type exports
export type RegisterInput = z.infer<typeof RegisterSchema>;
export type LoginInput = z.infer<typeof LoginSchema>;
export type CreateTodoInput = z.infer<typeof CreateTodoSchema>;
export type UpdateTodoInput = z.infer<typeof UpdateTodoSchema>;
export type CreateProjectInput = z.infer<typeof CreateProjectSchema>;
export type UpdateProjectInput = z.infer<typeof UpdateProjectSchema>;
export type CreateAreaInput = z.infer<typeof CreateAreaSchema>;
export type UpdateAreaInput = z.infer<typeof UpdateAreaSchema>;
export type CreateTagInput = z.infer<typeof CreateTagSchema>;
export type UpdateTagInput = z.infer<typeof UpdateTagSchema>;
export type SyncPushInput = z.infer<typeof SyncPushSchema>;
