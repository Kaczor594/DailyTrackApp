-- Tasks table
CREATE TABLE IF NOT EXISTS tasks (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    benchmark REAL NOT NULL DEFAULT 1.0,
    unit TEXT NOT NULL DEFAULT '',
    weight REAL NOT NULL DEFAULT 1.0,
    is_cumulative INTEGER NOT NULL DEFAULT 0,
    cumulative_period TEXT NOT NULL DEFAULT 'none',
    is_checkbox INTEGER NOT NULL DEFAULT 0,
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted INTEGER NOT NULL DEFAULT 0
);

-- Daily entries table
CREATE TABLE IF NOT EXISTS daily_entries (
    id TEXT PRIMARY KEY,
    task_id TEXT NOT NULL,
    date TEXT NOT NULL,
    value REAL NOT NULL DEFAULT 0.0,
    notes TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted INTEGER NOT NULL DEFAULT 0
);

-- Indexes for sync queries
CREATE INDEX IF NOT EXISTS idx_tasks_updated ON tasks(updated_at);
CREATE INDEX IF NOT EXISTS idx_entries_updated ON daily_entries(updated_at);
CREATE INDEX IF NOT EXISTS idx_entries_task_date ON daily_entries(task_id, date);
