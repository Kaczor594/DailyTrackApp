import Foundation
import SwiftData

/// Seeds initial task definitions on first launch.
/// These example tasks showcase the different task types available:
/// daily numeric, daily checkbox, weekly/monthly/yearly cumulative, and lifetime cumulative.
struct SeedData {
    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<TaskDefinition>()
        let existingTasks = (try? context.fetch(descriptor)) ?? []

        // Only seed if database is empty
        guard existingTasks.isEmpty else { return }

        // Reset sync timestamp so fresh seed doesn't conflict
        UserDefaults.standard.removeObject(forKey: "lastSyncTimestamp")

        // Deterministic IDs so all devices create identical tasks
        let initialTasks: [TaskDefinition] = [
            // Daily numeric task: track hours of reading per day
            TaskDefinition(
                id: "seed-reading",
                name: "Reading",
                benchmark: 1.0,
                unit: "hours",
                weight: 1.0,
                isCumulative: false,
                isCheckbox: false,
                sortOrder: 0
            ),
            // Daily checkbox task: did you exercise today?
            TaskDefinition(
                id: "seed-exercise",
                name: "Exercise",
                benchmark: 1.0,
                unit: "workout",
                weight: 1.0,
                isCumulative: false,
                isCheckbox: true,
                sortOrder: 1
            ),
            // Daily numeric task: track glasses of water
            TaskDefinition(
                id: "seed-water",
                name: "Water",
                benchmark: 8.0,
                unit: "glasses",
                weight: 0.5,
                isCumulative: false,
                isCheckbox: false,
                sortOrder: 2
            ),
            // Weekly cumulative task: complete 10 chores per week
            TaskDefinition(
                id: "seed-chores",
                name: "Chores",
                benchmark: 10.0,
                unit: "chores",
                weight: 1.0,
                isCumulative: true,
                cumulativePeriod: "week",
                isCheckbox: false,
                sortOrder: 3
            ),
            // Monthly cumulative task: read 4 books per month
            TaskDefinition(
                id: "seed-books",
                name: "Books",
                benchmark: 4.0,
                unit: "books",
                weight: 0.5,
                isCumulative: true,
                cumulativePeriod: "month",
                isCheckbox: false,
                sortOrder: 4
            ),
            // Yearly cumulative task: run 1000 km this year
            TaskDefinition(
                id: "seed-running",
                name: "Running",
                benchmark: 1000.0,
                unit: "km",
                weight: 0.5,
                isCumulative: true,
                cumulativePeriod: "year",
                isCheckbox: false,
                sortOrder: 5
            ),
            // Lifetime cumulative task: track total study hours (no period)
            TaskDefinition(
                id: "seed-study-hours",
                name: "Study Hours",
                benchmark: 500.0,
                unit: "hours",
                weight: 1.0,
                isCumulative: true,
                isCheckbox: false,
                sortOrder: 6
            ),
        ]

        for task in initialTasks {
            context.insert(task)
        }

        try? context.save()

        // Seed historical data
        seedHistoricalEntries(context: context)
    }

    private static func seedHistoricalEntries(context: ModelContext) {
        let descriptor = FetchDescriptor<TaskDefinition>()
        let tasks = (try? context.fetch(descriptor)) ?? []
        let taskMap = Dictionary(tasks.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        let historicalData: [(date: String, entries: [(name: String, value: Double)])] = [
            ("2026-02-24", [("Reading", 1.5), ("Exercise", 1), ("Water", 7), ("Chores", 2), ("Books", 0), ("Running", 5.0), ("Study Hours", 2)]),
            ("2026-02-25", [("Reading", 0.5), ("Exercise", 0), ("Water", 8), ("Chores", 3), ("Books", 0), ("Running", 0), ("Study Hours", 3)]),
            ("2026-02-26", [("Reading", 1.0), ("Exercise", 1), ("Water", 6), ("Chores", 1), ("Books", 1), ("Running", 8.0), ("Study Hours", 1)]),
            ("2026-02-27", [("Reading", 0), ("Exercise", 1), ("Water", 8), ("Chores", 0), ("Books", 0), ("Running", 0), ("Study Hours", 0)]),
            ("2026-02-28", [("Reading", 2.0), ("Exercise", 0), ("Water", 5), ("Chores", 2), ("Books", 0), ("Running", 6.5), ("Study Hours", 4)]),
            ("2026-03-01", [("Reading", 1.0), ("Exercise", 1), ("Water", 8), ("Chores", 1), ("Books", 0), ("Running", 10.0), ("Study Hours", 2)]),
            ("2026-03-02", [("Reading", 0.5), ("Exercise", 1), ("Water", 7), ("Chores", 0), ("Books", 1), ("Running", 5.0), ("Study Hours", 1)]),
            ("2026-03-03", [("Reading", 1.0), ("Exercise", 0), ("Water", 6), ("Chores", 3), ("Books", 0), ("Running", 0), ("Study Hours", 3)]),
            ("2026-03-04", [("Reading", 1.5), ("Exercise", 1), ("Water", 8), ("Chores", 2), ("Books", 0), ("Running", 7.0), ("Study Hours", 2)]),
            ("2026-03-05", [("Reading", 0), ("Exercise", 1), ("Water", 7), ("Chores", 1), ("Books", 1), ("Running", 4.5), ("Study Hours", 1)]),
        ]

        for day in historicalData {
            for entry in day.entries {
                guard let task = taskMap[entry.name] else { continue }
                let entryId = "seed-\(entry.name.lowercased().replacingOccurrences(of: " ", with: "-"))-\(day.date)"
                let dailyEntry = DailyEntry(
                    id: entryId,
                    task: task,
                    date: day.date,
                    value: entry.value
                )
                context.insert(dailyEntry)
            }
        }

        try? context.save()
    }
}
