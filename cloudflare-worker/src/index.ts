interface Env {
  DB: D1Database;
  SYNC_TOKEN: string;
}

async function ensureCumulativePeriodColumn(db: D1Database) {
  try {
    await db.prepare("SELECT cumulative_period FROM tasks LIMIT 1").first();
  } catch {
    await db.prepare("ALTER TABLE tasks ADD COLUMN cumulative_period TEXT NOT NULL DEFAULT 'none'").run();
  }
}

async function ensureSyncedAtColumn(db: D1Database) {
  // Auto-migration: add synced_at column if it doesn't exist.
  // synced_at uses server time and is used for pull queries,
  // while updated_at keeps the client timestamp for conflict resolution.
  try {
    await db.prepare("SELECT synced_at FROM tasks LIMIT 1").first();
  } catch {
    await db.prepare("ALTER TABLE tasks ADD COLUMN synced_at TEXT NOT NULL DEFAULT ''").run();
    await db.prepare("UPDATE tasks SET synced_at = updated_at WHERE synced_at = ''").run();
    await db.prepare("CREATE INDEX IF NOT EXISTS idx_tasks_synced ON tasks(synced_at)").run();

    await db.prepare("ALTER TABLE daily_entries ADD COLUMN synced_at TEXT NOT NULL DEFAULT ''").run();
    await db.prepare("UPDATE daily_entries SET synced_at = updated_at WHERE synced_at = ''").run();
    await db.prepare("CREATE INDEX IF NOT EXISTS idx_entries_synced ON daily_entries(synced_at)").run();
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const corsHeaders = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
    };

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    const authHeader = request.headers.get("Authorization");
    const token = authHeader?.replace("Bearer ", "");
    if (token !== env.SYNC_TOKEN) {
      return Response.json({ error: "Unauthorized" }, { status: 401, headers: corsHeaders });
    }

    // Run migrations if needed
    await ensureSyncedAtColumn(env.DB);
    await ensureCumulativePeriodColumn(env.DB);

    const url = new URL(request.url);
    const path = url.pathname;

    try {
      // GET /sync?since=<ISO8601> — pull changes since timestamp
      // Uses synced_at (server time) so there are no client clock issues.
      if (request.method === "GET" && path === "/sync") {
        const since = url.searchParams.get("since") || "1970-01-01T00:00:00Z";

        const tasks = await env.DB.prepare(
          "SELECT * FROM tasks WHERE synced_at > ?"
        ).bind(since).all();

        const entries = await env.DB.prepare(
          "SELECT * FROM daily_entries WHERE synced_at > ?"
        ).bind(since).all();

        return Response.json({
          tasks: tasks.results,
          entries: entries.results,
          server_time: new Date().toISOString(),
        }, { headers: corsHeaders });
      }

      // POST /sync — push changes (upsert)
      // updated_at is the client's timestamp, used for conflict resolution.
      // synced_at is set to server time on every successful upsert.
      if (request.method === "POST" && path === "/sync") {
        const body = await request.json() as {
          tasks?: any[];
          entries?: any[];
        };

        const now = new Date().toISOString();
        let tasksUpserted = 0;
        let entriesUpserted = 0;

        if (body.tasks) {
          for (const task of body.tasks) {
            const existing = await env.DB.prepare(
              "SELECT updated_at, deleted FROM tasks WHERE id = ?"
            ).bind(task.id).first();

            if (existing) {
              // Deletion wins: once deleted on server, never resurrect via sync
              if ((existing as any).deleted === 1 && !(task.deleted ? 1 : 0)) {
                continue;
              }
              // Only update if incoming client timestamp is newer
              if (task.updated_at <= (existing as any).updated_at) {
                continue;
              }
            }

            await env.DB.prepare(`
              INSERT INTO tasks (id, name, benchmark, unit, weight, is_cumulative, cumulative_period, is_checkbox, sort_order, is_active, created_at, updated_at, deleted, synced_at)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                benchmark = excluded.benchmark,
                unit = excluded.unit,
                weight = excluded.weight,
                is_cumulative = excluded.is_cumulative,
                cumulative_period = excluded.cumulative_period,
                is_checkbox = excluded.is_checkbox,
                sort_order = excluded.sort_order,
                is_active = excluded.is_active,
                updated_at = excluded.updated_at,
                deleted = excluded.deleted,
                synced_at = excluded.synced_at
            `).bind(
              task.id, task.name, task.benchmark, task.unit, task.weight,
              task.is_cumulative ? 1 : 0, task.cumulative_period || 'none',
              task.is_checkbox ? 1 : 0,
              task.sort_order, task.is_active ? 1 : 0,
              task.created_at, task.updated_at, task.deleted ? 1 : 0,
              now
            ).run();
            tasksUpserted++;
          }
        }

        if (body.entries) {
          for (const entry of body.entries) {
            const existing = await env.DB.prepare(
              "SELECT updated_at, deleted FROM daily_entries WHERE id = ?"
            ).bind(entry.id).first();

            if (existing) {
              if ((existing as any).deleted === 1 && !(entry.deleted ? 1 : 0)) {
                continue;
              }
              if (entry.updated_at <= (existing as any).updated_at) {
                continue;
              }
            }

            await env.DB.prepare(`
              INSERT INTO daily_entries (id, task_id, date, value, notes, created_at, updated_at, deleted, synced_at)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
              ON CONFLICT(id) DO UPDATE SET
                task_id = excluded.task_id,
                date = excluded.date,
                value = excluded.value,
                notes = excluded.notes,
                updated_at = excluded.updated_at,
                deleted = excluded.deleted,
                synced_at = excluded.synced_at
            `).bind(
              entry.id, entry.task_id, entry.date, entry.value,
              entry.notes || null, entry.created_at, entry.updated_at,
              entry.deleted ? 1 : 0, now
            ).run();
            entriesUpserted++;
          }
        }

        return Response.json({
          tasks_upserted: tasksUpserted,
          entries_upserted: entriesUpserted,
          server_time: now,
        }, { headers: corsHeaders });
      }

      // POST /reconcile — mark server tasks not in the provided list as deleted
      if (request.method === "POST" && path === "/reconcile") {
        const body = await request.json() as { active_task_ids: string[] };
        const activeIds = body.active_task_ids || [];
        const now = new Date().toISOString();

        if (activeIds.length === 0) {
          return Response.json({ error: "active_task_ids required" }, { status: 400, headers: corsHeaders });
        }

        const placeholders = activeIds.map(() => "?").join(",");
        const result = await env.DB.prepare(
          `UPDATE tasks SET deleted = 1, updated_at = ?, synced_at = ? WHERE deleted = 0 AND id NOT IN (${placeholders})`
        ).bind(now, now, ...activeIds).run();

        await env.DB.prepare(
          `UPDATE daily_entries SET deleted = 1, updated_at = ?, synced_at = ? WHERE deleted = 0 AND task_id NOT IN (${placeholders})`
        ).bind(now, now, ...activeIds).run();

        return Response.json({
          tasks_marked_deleted: result.meta.changes,
          server_time: now,
        }, { headers: corsHeaders });
      }

      // DELETE /tasks/:id — soft delete
      if (request.method === "DELETE" && path.startsWith("/tasks/")) {
        const id = path.split("/tasks/")[1];
        const now = new Date().toISOString();
        await env.DB.prepare(
          "UPDATE tasks SET deleted = 1, updated_at = ?, synced_at = ? WHERE id = ?"
        ).bind(now, now, id).run();
        await env.DB.prepare(
          "UPDATE daily_entries SET deleted = 1, updated_at = ?, synced_at = ? WHERE task_id = ?"
        ).bind(now, now, id).run();
        return Response.json({ ok: true, server_time: now }, { headers: corsHeaders });
      }

      // DELETE /entries/:id — soft delete
      if (request.method === "DELETE" && path.startsWith("/entries/")) {
        const id = path.split("/entries/")[1];
        const now = new Date().toISOString();
        await env.DB.prepare(
          "UPDATE daily_entries SET deleted = 1, updated_at = ?, synced_at = ? WHERE id = ?"
        ).bind(now, now, id).run();
        return Response.json({ ok: true, server_time: now }, { headers: corsHeaders });
      }

      return Response.json({ error: "Not found" }, { status: 404, headers: corsHeaders });

    } catch (err: any) {
      return Response.json({ error: err.message }, { status: 500, headers: corsHeaders });
    }
  },
};
