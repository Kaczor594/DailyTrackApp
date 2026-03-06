import AppIntents
import SwiftData
import WidgetKit

struct ToggleTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Task"
    static var description = IntentDescription("Toggle a checkbox task's completion status")

    @Parameter(title: "Task ID")
    var taskId: String

    init() {
        self.taskId = ""
    }

    init(taskId: String) {
        self.taskId = taskId
    }

    func perform() async throws -> some IntentResult {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayStr = dateFormatter.string(from: Date())

        do {
            let schema = Schema([TaskDefinition.self, DailyEntry.self])
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                groupContainer: .identifier(AppGroupContainer.appGroupIdentifier)
            )
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)

            // Find the task
            let taskIdToFind = taskId
            let taskDescriptor = FetchDescriptor<TaskDefinition>(
                predicate: #Predicate { $0.id == taskIdToFind }
            )
            guard let task = try context.fetch(taskDescriptor).first else {
                return .result()
            }

            // Find or create today's entry for this task
            let entryDescriptor = FetchDescriptor<DailyEntry>(
                predicate: #Predicate { $0.date == todayStr && $0.task?.id == taskIdToFind && $0.deleted == false }
            )
            let existingEntry = try context.fetch(entryDescriptor).first

            if let entry = existingEntry {
                // Toggle the value
                entry.value = entry.value > 0 ? 0 : 1
                entry.updatedAt = ISO8601DateFormatter().string(from: Date())
            } else {
                // Create new entry with value 1 (completed)
                let entryId = "\(taskId)-\(todayStr)"
                let newEntry = DailyEntry(
                    id: entryId,
                    task: task,
                    date: todayStr,
                    value: 1,
                    updatedAt: ISO8601DateFormatter().string(from: Date())
                )
                context.insert(newEntry)
            }

            try context.save()

        } catch {
            print("Failed to toggle task: \(error)")
        }

        // Reload widget timelines
        WidgetCenter.shared.reloadAllTimelines()

        return .result()
    }
}
