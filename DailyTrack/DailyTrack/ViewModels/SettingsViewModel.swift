import Foundation
import SwiftUI
import SwiftData
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// View model for the task configuration / settings screen.
@Observable
final class SettingsViewModel {
    var tasks: [TaskDefinition] = []
    var editingTask: TaskDefinition?
    var showingAddSheet = false
    var showingEditSheet = false

    private var modelContext: ModelContext?

    func loadTasks(context: ModelContext) {
        self.modelContext = context
        let descriptor = FetchDescriptor<TaskDefinition>(
            predicate: #Predicate { $0.deleted == false },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
        )
        tasks = (try? context.fetch(descriptor)) ?? []
    }

    func addTask(_ task: TaskDefinition) {
        guard let context = modelContext else { return }
        task.sortOrder = tasks.count
        context.insert(task)
        try? context.save()
        loadTasks(context: context)
    }

    func updateTask(_ task: TaskDefinition) {
        guard let context = modelContext else { return }
        task.markUpdated()
        try? context.save()
        loadTasks(context: context)
    }

    func deleteTask(_ task: TaskDefinition) {
        guard let context = modelContext else { return }
        task.deleted = true
        task.markUpdated()
        // Also soft-delete entries
        if let entries = task.entries {
            for entry in entries {
                entry.deleted = true
                entry.markUpdated()
            }
        }
        try? context.save()
        loadTasks(context: context)
    }

    func moveTask(from source: IndexSet, to destination: Int) {
        guard let context = modelContext else { return }
        tasks.move(fromOffsets: source, toOffset: destination)
        for (index, task) in tasks.enumerated() {
            if task.sortOrder != index {
                task.sortOrder = index
                task.markUpdated()
            }
        }
        try? context.save()
    }

    func toggleActive(_ task: TaskDefinition) {
        guard let context = modelContext else { return }
        task.isActive.toggle()
        task.markUpdated()
        try? context.save()
        loadTasks(context: context)
    }

    // MARK: - JSON Export/Import

    func exportJSON() -> Data? {
        let codableTasks = tasks.map { CodableTaskDefinition(from: $0) }
        return try? JSONEncoder().encode(codableTasks)
    }

    func importJSON(_ data: Data) {
        guard let context = modelContext else { return }
        guard let codableTasks = try? JSONDecoder().decode([CodableTaskDefinition].self, from: data) else { return }
        for ct in codableTasks {
            let task = TaskDefinition(
                id: ct.id,
                name: ct.name,
                benchmark: ct.benchmark,
                unit: ct.unit,
                weight: ct.weight,
                isCumulative: ct.isCumulative,
                cumulativePeriod: ct.cumulativePeriod,
                isCheckbox: ct.isCheckbox,
                sortOrder: ct.sortOrder,
                isActive: ct.isActive,
                createdAt: ct.createdAt
            )
            context.insert(task)
        }
        try? context.save()
        loadTasks(context: context)
    }

    func configFilePath() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("DailyTrack/tasks_config.json")
    }

    func saveConfigFile() {
        guard let data = exportJSON() else { return }
        let dir = configFilePath().deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: configFilePath())
    }

    func loadConfigFile() {
        let path = configFilePath()
        guard let data = try? Data(contentsOf: path) else { return }
        importJSON(data)
    }
}
