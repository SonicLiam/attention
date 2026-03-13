-- Migration 001: Initial schema for Attention sync server
-- Matches Swift models: Todo, Project, Area, Tag, ChecklistItem, Recurrence, Heading

BEGIN;

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    display_name VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Areas
CREATE TABLE IF NOT EXISTS areas (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    version BIGINT NOT NULL DEFAULT 1
);

CREATE INDEX idx_areas_user_id ON areas(user_id);
CREATE INDEX idx_areas_updated_at ON areas(updated_at);

-- Projects
CREATE TABLE IF NOT EXISTS projects (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    notes TEXT NOT NULL DEFAULT '',
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    deadline TIMESTAMPTZ,
    sort_order INT NOT NULL DEFAULT 0,
    area_id UUID REFERENCES areas(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    version BIGINT NOT NULL DEFAULT 1
);

CREATE INDEX idx_projects_user_id ON projects(user_id);
CREATE INDEX idx_projects_area_id ON projects(area_id);
CREATE INDEX idx_projects_updated_at ON projects(updated_at);

-- Headings (project sections)
CREATE TABLE IF NOT EXISTS headings (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    sort_order INT NOT NULL DEFAULT 0,
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    version BIGINT NOT NULL DEFAULT 1
);

CREATE INDEX idx_headings_project_id ON headings(project_id);

-- Tags
CREATE TABLE IF NOT EXISTS tags (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    color VARCHAR(20) NOT NULL DEFAULT '#6366F1',
    sort_order INT NOT NULL DEFAULT 0,
    parent_tag_id UUID REFERENCES tags(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    version BIGINT NOT NULL DEFAULT 1
);

CREATE INDEX idx_tags_user_id ON tags(user_id);
CREATE INDEX idx_tags_parent_tag_id ON tags(parent_tag_id);
CREATE INDEX idx_tags_updated_at ON tags(updated_at);

-- Todos
CREATE TABLE IF NOT EXISTS todos (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(500) NOT NULL,
    notes TEXT NOT NULL DEFAULT '',
    status VARCHAR(20) NOT NULL DEFAULT 'inbox',
    priority INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    scheduled_date TIMESTAMPTZ,
    deadline TIMESTAMPTZ,
    sort_order INT NOT NULL DEFAULT 0,
    heading_id UUID REFERENCES headings(id) ON DELETE SET NULL,
    project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
    area_id UUID REFERENCES areas(id) ON DELETE SET NULL,
    deleted_at TIMESTAMPTZ,
    version BIGINT NOT NULL DEFAULT 1
);

CREATE INDEX idx_todos_user_id ON todos(user_id);
CREATE INDEX idx_todos_project_id ON todos(project_id);
CREATE INDEX idx_todos_area_id ON todos(area_id);
CREATE INDEX idx_todos_status ON todos(status);
CREATE INDEX idx_todos_scheduled_date ON todos(scheduled_date);
CREATE INDEX idx_todos_updated_at ON todos(updated_at);

-- Todo-Tag junction table
CREATE TABLE IF NOT EXISTS todo_tags (
    todo_id UUID NOT NULL REFERENCES todos(id) ON DELETE CASCADE,
    tag_id UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (todo_id, tag_id)
);

CREATE INDEX idx_todo_tags_tag_id ON todo_tags(tag_id);

-- Checklist items
CREATE TABLE IF NOT EXISTS checklist_items (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    todo_id UUID NOT NULL REFERENCES todos(id) ON DELETE CASCADE,
    title VARCHAR(500) NOT NULL,
    is_completed BOOLEAN NOT NULL DEFAULT FALSE,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    version BIGINT NOT NULL DEFAULT 1
);

CREATE INDEX idx_checklist_items_todo_id ON checklist_items(todo_id);

-- Recurrences
CREATE TABLE IF NOT EXISTS recurrences (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    todo_id UUID NOT NULL REFERENCES todos(id) ON DELETE CASCADE,
    frequency VARCHAR(20) NOT NULL DEFAULT 'daily',
    interval INT NOT NULL DEFAULT 1,
    days_of_week INT[],
    day_of_month INT,
    end_date TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    version BIGINT NOT NULL DEFAULT 1
);

CREATE INDEX idx_recurrences_todo_id ON recurrences(todo_id);

-- Sync log for incremental sync
CREATE TABLE IF NOT EXISTS sync_log (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    entity_type VARCHAR(50) NOT NULL,
    entity_id UUID NOT NULL,
    action VARCHAR(20) NOT NULL,
    version BIGINT NOT NULL,
    payload JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sync_log_user_id_id ON sync_log(user_id, id);
CREATE INDEX idx_sync_log_entity ON sync_log(entity_type, entity_id);

-- Refresh tokens
CREATE TABLE IF NOT EXISTS refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL,
    device_name VARCHAR(255),
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_token_hash ON refresh_tokens(token_hash);

COMMIT;
