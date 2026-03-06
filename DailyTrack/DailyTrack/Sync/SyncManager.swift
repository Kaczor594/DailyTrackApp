import Foundation
import SwiftData

/// Manages bidirectional sync between local SwiftData and Cloudflare D1.
@Observable
final class SyncManager {
    var isSyncing = false
    var lastSyncDate: Date?
    var syncVersion: Int = 0
    var lastError: String?

    var apiURL: String {
        didSet { UserDefaults.standard.set(apiURL, forKey: "syncAPIURL") }
    }

    var syncToken: String {
        didSet { UserDefaults.standard.set(syncToken, forKey: "syncToken") }
    }

    var syncEnabled: Bool {
        !apiURL.isEmpty && !syncToken.isEmpty
    }

    private var autoSyncTask: Task<Void, Never>?
    private var debouncedSyncTask: Task<Void, Never>?

    private var lastSyncTimestamp: String {
        get { UserDefaults.standard.string(forKey: "lastSyncTimestamp") ?? "1970-01-01T00:00:00Z" }
        set { UserDefaults.standard.set(newValue, forKey: "lastSyncTimestamp") }
    }

    init() {
        self.apiURL = UserDefaults.standard.string(forKey: "syncAPIURL") ?? ""
        self.syncToken = UserDefaults.standard.string(forKey: "syncToken") ?? ""
    }

    // MARK: - Auto Sync

    /// Debounced sync: waits 2 seconds after last call before syncing.
    /// Use this for on-change triggers to avoid hammering the API.
    func debouncedSync(context: ModelContext) {
        debouncedSyncTask?.cancel()
        debouncedSyncTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await sync(context: context)
        }
    }

    func startAutoSync(context: ModelContext, interval: TimeInterval = 60) {
        autoSyncTask?.cancel()
        autoSyncTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await sync(context: context)
            }
        }
    }

    func stopAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
    }

    // MARK: - Sync

    func sync(context: ModelContext) async {
        guard syncEnabled, !isSyncing else { return }

        await MainActor.run { isSyncing = true; lastError = nil }

        do {
            let isFirstSync = lastSyncTimestamp == "1970-01-01T00:00:00Z"

            // 1. Push local changes (including all deletions)
            try await pushChanges(context: context)

            // 2. Pull remote changes
            try await pullChanges(context: context)

            // 3. Reconcile: tell server which tasks are active locally,
            //    so it marks any stale/legacy tasks as deleted.
            //    Skip on first sync — the device doesn't have full state yet,
            //    so reconciling would incorrectly delete server-only tasks.
            if !isFirstSync {
                try await reconcile(context: context)
            }

            await MainActor.run {
                self.lastSyncDate = Date()
                self.syncVersion += 1
                self.isSyncing = false
            }
        } catch {
            await MainActor.run {
                self.lastError = error.localizedDescription
                self.isSyncing = false
            }
        }
    }

    // MARK: - Push

    private func pushChanges(context: ModelContext) async throws {
        let since = lastSyncTimestamp

        // Fetch locally modified tasks
        let recentTasks: [TaskDefinition] = try context.fetch(FetchDescriptor<TaskDefinition>(
            predicate: #Predicate { $0.updatedAt > since }
        ))

        // Always re-push all locally deleted tasks to ensure the server
        // knows about deletions, even if they were deleted before the last sync.
        let deletedTasks: [TaskDefinition] = try context.fetch(FetchDescriptor<TaskDefinition>(
            predicate: #Predicate { $0.deleted == true }
        ))

        // Merge both lists, deduplicating by ID
        var taskMap: [String: TaskDefinition] = [:]
        for task in recentTasks { taskMap[task.id] = task }
        for task in deletedTasks { taskMap[task.id] = task }
        let allTasks = Array(taskMap.values)

        // Fetch locally modified entries
        let allEntries: [DailyEntry] = try context.fetch(FetchDescriptor<DailyEntry>(
            predicate: #Predicate { $0.updatedAt > since }
        ))

        guard !allTasks.isEmpty || !allEntries.isEmpty else { return }

        let payload: [String: Any] = [
            "tasks": allTasks.map { t -> [String: Any] in
                [
                    "id": t.id, "name": t.name, "benchmark": t.benchmark,
                    "unit": t.unit, "weight": t.weight,
                    "is_cumulative": t.isCumulative, "cumulative_period": t.cumulativePeriod ?? "none",
                    "is_checkbox": t.isCheckbox,
                    "sort_order": t.sortOrder, "is_active": t.isActive,
                    "created_at": t.createdAt, "updated_at": t.updatedAt,
                    "deleted": t.deleted
                ]
            },
            "entries": allEntries.map { e -> [String: Any] in
                var dict: [String: Any] = [
                    "id": e.id, "task_id": e.task?.id ?? "",
                    "date": e.date, "value": e.value,
                    "created_at": e.updatedAt, "updated_at": e.updatedAt,
                    "deleted": e.deleted
                ]
                if let notes = e.notes { dict["notes"] = notes }
                return dict
            }
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: URL(string: "\(apiURL)/sync")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(syncToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SyncError.pushFailed
        }
    }

    // MARK: - Reconcile

    /// Tells the server which task IDs are active locally.
    /// The server marks any task NOT in this list as deleted,
    /// preventing stale tasks from being pulled back.
    private func reconcile(context: ModelContext) async throws {
        let activeTasks: [TaskDefinition] = try context.fetch(FetchDescriptor<TaskDefinition>(
            predicate: #Predicate { $0.deleted == false }
        ))

        let activeIds = activeTasks.map { $0.id }
        guard !activeIds.isEmpty else { return }

        let payload: [String: Any] = ["active_task_ids": activeIds]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: URL(string: "\(apiURL)/reconcile")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(syncToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SyncError.reconcileFailed
        }
    }

    // MARK: - Pull

    private func pullChanges(context: ModelContext) async throws {
        let since = lastSyncTimestamp

        var request = URLRequest(url: URL(string: "\(apiURL)/sync?since=\(since)")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(syncToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SyncError.pullFailed
        }

        let syncResponse = try JSONDecoder().decode(SyncResponse.self, from: data)

        // Merge tasks
        for remoteTask in syncResponse.tasks {
            let taskId = remoteTask.id
            let existing: [TaskDefinition] = try context.fetch(FetchDescriptor<TaskDefinition>(
                predicate: #Predicate { $0.id == taskId }
            ))

            if let local = existing.first {
                // Deletion wins: never resurrect a locally deleted task
                if local.deleted && !remoteTask.deleted {
                    continue
                }

                // Remote deletion always wins regardless of timestamps
                if remoteTask.deleted && !local.deleted {
                    local.deleted = true
                    local.updatedAt = remoteTask.updatedAt
                    // Also soft-delete associated entries
                    if let entries = local.entries {
                        for entry in entries {
                            entry.deleted = true
                            entry.markUpdated()
                        }
                    }
                    continue
                }

                // Last-write-wins for non-deletion updates
                if remoteTask.updatedAt > local.updatedAt {
                    local.name = remoteTask.name
                    local.benchmark = remoteTask.benchmark
                    local.unit = remoteTask.unit
                    local.weight = remoteTask.weight
                    local.isCumulative = remoteTask.isCumulative
                    local.cumulativePeriod = remoteTask.cumulativePeriod
                    local.isCheckbox = remoteTask.isCheckbox
                    local.sortOrder = remoteTask.sortOrder
                    local.isActive = remoteTask.isActive
                    local.updatedAt = remoteTask.updatedAt
                    local.deleted = remoteTask.deleted
                }
            } else {
                // Task doesn't exist locally.
                // Skip if already deleted on server — no need to insert.
                if remoteTask.deleted {
                    continue
                }

                // If we have synced before (not a fresh device), and this task
                // was created before our last sync, we should have received it
                // previously. The fact that we don't have it means it was
                // deleted locally. Don't re-insert stale tasks.
                let isFirstSync = since == "1970-01-01T00:00:00Z"
                if !isFirstSync && remoteTask.createdAt < since {
                    continue
                }

                let newTask = TaskDefinition(
                    id: remoteTask.id,
                    name: remoteTask.name,
                    benchmark: remoteTask.benchmark,
                    unit: remoteTask.unit,
                    weight: remoteTask.weight,
                    isCumulative: remoteTask.isCumulative,
                    cumulativePeriod: remoteTask.cumulativePeriod,
                    isCheckbox: remoteTask.isCheckbox,
                    sortOrder: remoteTask.sortOrder,
                    isActive: remoteTask.isActive,
                    createdAt: remoteTask.createdAt,
                    updatedAt: remoteTask.updatedAt,
                    deleted: remoteTask.deleted
                )
                context.insert(newTask)
            }
        }

        // Merge entries
        for remoteEntry in syncResponse.entries {
            let entryId = remoteEntry.id
            let existing: [DailyEntry] = try context.fetch(FetchDescriptor<DailyEntry>(
                predicate: #Predicate { $0.id == entryId }
            ))

            if let local = existing.first {
                // Deletion wins: never resurrect a locally deleted entry
                if local.deleted && !remoteEntry.deleted {
                    continue
                }

                // Remote deletion always wins regardless of timestamps
                if remoteEntry.deleted && !local.deleted {
                    local.deleted = true
                    local.updatedAt = remoteEntry.updatedAt
                    continue
                }

                if remoteEntry.updatedAt > local.updatedAt {
                    local.value = remoteEntry.value
                    local.notes = remoteEntry.notes
                    local.updatedAt = remoteEntry.updatedAt
                    local.deleted = remoteEntry.deleted

                    // Re-link task if needed
                    if local.task?.id != remoteEntry.taskId {
                        let taskId = remoteEntry.taskId
                        let tasks: [TaskDefinition] = (try? context.fetch(FetchDescriptor<TaskDefinition>(
                            predicate: #Predicate { $0.id == taskId }
                        ))) ?? []
                        local.task = tasks.first
                    }
                }
            } else {
                // Skip deleted entries — no need to insert
                if remoteEntry.deleted {
                    continue
                }

                // Skip stale entries (see task logic above)
                let isFirstSync = since == "1970-01-01T00:00:00Z"
                if !isFirstSync && remoteEntry.updatedAt < since {
                    continue
                }

                // Find the parent task
                let taskId = remoteEntry.taskId
                let tasks: [TaskDefinition] = (try? context.fetch(FetchDescriptor<TaskDefinition>(
                    predicate: #Predicate { $0.id == taskId }
                ))) ?? []

                let newEntry = DailyEntry(
                    id: remoteEntry.id,
                    task: tasks.first,
                    date: remoteEntry.date,
                    value: remoteEntry.value,
                    notes: remoteEntry.notes,
                    updatedAt: remoteEntry.updatedAt,
                    deleted: remoteEntry.deleted
                )
                context.insert(newEntry)
            }
        }

        try context.save()
        lastSyncTimestamp = syncResponse.serverTime
    }

    enum SyncError: LocalizedError {
        case pushFailed, pullFailed, reconcileFailed

        var errorDescription: String? {
            switch self {
            case .pushFailed: return "Failed to push changes to server"
            case .pullFailed: return "Failed to pull changes from server"
            case .reconcileFailed: return "Failed to reconcile with server"
            }
        }
    }
}

// MARK: - Sync Response Model

private struct SyncResponse: Codable {
    let tasks: [CodableTaskDefinition]
    let entries: [CodableDailyEntry]
    let serverTime: String

    enum CodingKeys: String, CodingKey {
        case tasks, entries
        case serverTime = "server_time"
    }
}
