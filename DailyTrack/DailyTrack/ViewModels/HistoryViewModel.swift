import Foundation
import SwiftData

/// View model for the history and analytics views.
@Observable
final class HistoryViewModel {
    var dailyScores: [(date: String, score: Double)] = []
    var tasks: [TaskDefinition] = []
    var selectedPeriod: Period = .month
    var currentStreak: Int = 0
    var bestStreak: Int = 0
    var averageScore: Double = 0
    var totalDaysTracked: Int = 0

    private var modelContext: ModelContext?

    enum Period: String, CaseIterable {
        case week, month, quarter, year

        var displayName: String {
            switch self {
            case .week: return String(localized: "Week")
            case .month: return String(localized: "Month")
            case .quarter: return String(localized: "Quarter")
            case .year: return String(localized: "Year")
            }
        }

        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .quarter: return 90
            case .year: return 365
            }
        }
    }

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func loadData(context: ModelContext) {
        self.modelContext = context

        tasks = fetchActiveTasks(context: context)
        let scoringTasks = tasks.filter { !$0.isCumulative || $0.hasPeriod }
        let totalWeight = scoringTasks.reduce(0.0) { $0 + $1.weight }

        let endDate = dateFormatter.string(from: Date())
        let startDateValue = Calendar.current.date(byAdding: .day, value: -selectedPeriod.days, to: Date())!
        let startDate = dateFormatter.string(from: startDateValue)

        // Fetch entries in date range
        let allEntries: [DailyEntry] = (try? context.fetch(FetchDescriptor<DailyEntry>(
            predicate: #Predicate { $0.date >= startDate && $0.date <= endDate && $0.deleted == false }
        ))) ?? []

        // Group by date and compute scores
        var dateEntries: [String: [DailyEntry]] = [:]
        for entry in allEntries {
            dateEntries[entry.date, default: []].append(entry)
        }

        dailyScores = dateEntries.map { (date, entries) in
            guard totalWeight > 0 else { return (date, 0.0) }
            let entryDate = dateFormatter.date(from: date) ?? Date()
            let entryMap = Dictionary(entries.compactMap { e in
                e.task.map { ($0.id, e) }
            }, uniquingKeysWith: { first, _ in first })
            var weightedSum = 0.0
            for task in scoringTasks {
                let value = entryMap[task.id]?.value ?? 0
                let ratio: Double
                if task.isCheckbox {
                    ratio = value > 0 ? 1.0 : 0.0
                } else if task.hasPeriod, let pw = periodWindow(for: task, on: entryDate) {
                    let dailyTarget = task.benchmark / Double(pw.periodDays)
                    ratio = dailyTarget > 0 ? value / dailyTarget : 0
                } else {
                    ratio = task.benchmark > 0 ? value / task.benchmark : 0
                }
                weightedSum += ratio * task.weight
            }
            return (date, weightedSum / totalWeight)
        }.sorted { $0.date < $1.date }

        // Stats
        if !dailyScores.isEmpty {
            averageScore = dailyScores.reduce(0) { $0 + $1.score } / Double(dailyScores.count)
            totalDaysTracked = dailyScores.count
        } else {
            averageScore = 0
            totalDaysTracked = 0
        }

        currentStreak = computeCurrentStreak(context: context)
        bestStreak = calculateBestStreak()
    }

    private func fetchActiveTasks(context: ModelContext) -> [TaskDefinition] {
        let descriptor = FetchDescriptor<TaskDefinition>(
            predicate: #Predicate { $0.isActive == true && $0.deleted == false },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func calculateBestStreak() -> Int {
        var best = 0
        var current = 0
        let threshold = 0.7

        let sorted = dailyScores.sorted { $0.date < $1.date }
        var previousDate: Date?

        for entry in sorted {
            guard let date = dateFormatter.date(from: entry.date) else { continue }

            if let prev = previousDate {
                let dayDiff = Calendar.current.dateComponents([.day], from: prev, to: date).day ?? 0
                if dayDiff == 1 && entry.score >= threshold {
                    current += 1
                } else if entry.score >= threshold {
                    current = 1
                } else {
                    current = 0
                }
            } else if entry.score >= threshold {
                current = 1
            }

            best = max(best, current)
            previousDate = date
        }
        return best
    }

    private func computeCurrentStreak(context: ModelContext, threshold: Double = 0.7) -> Int {
        let scoringTasks = tasks.filter { !$0.isCumulative || $0.hasPeriod }
        guard !scoringTasks.isEmpty else { return 0 }
        let totalWeight = scoringTasks.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 0 }

        let allEntries: [DailyEntry] = (try? context.fetch(FetchDescriptor<DailyEntry>())) ?? []
        var dateEntries: [String: [DailyEntry]] = [:]
        for entry in allEntries {
            dateEntries[entry.date, default: []].append(entry)
        }

        var dateScores: [String: Double] = [:]
        for (date, entries) in dateEntries {
            guard let entryDate = dateFormatter.date(from: date) else { continue }
            let entryMap = Dictionary(entries.compactMap { e in
                e.task.map { ($0.id, e) }
            }, uniquingKeysWith: { first, _ in first })
            var weightedSum = 0.0
            for task in scoringTasks {
                let value = entryMap[task.id]?.value ?? 0
                let ratio: Double
                if task.isCheckbox {
                    ratio = value > 0 ? 1.0 : 0.0
                } else if task.hasPeriod, let pw = periodWindow(for: task, on: entryDate) {
                    let dailyTarget = task.benchmark / Double(pw.periodDays)
                    ratio = dailyTarget > 0 ? value / dailyTarget : 0
                } else {
                    ratio = task.benchmark > 0 ? value / task.benchmark : 0
                }
                weightedSum += ratio * task.weight
            }
            dateScores[date] = weightedSum / totalWeight
        }

        var streak = 0
        var expectedDate = Calendar.current.startOfDay(for: Date())
        while true {
            let dateStr = dateFormatter.string(from: expectedDate)
            guard let score = dateScores[dateStr], score >= threshold else { break }
            streak += 1
            expectedDate = Calendar.current.date(byAdding: .day, value: -1, to: expectedDate)!
        }
        return streak
    }

    /// Calendar heatmap data: date string -> score (0 to 1)
    func heatmapData() -> [String: Double] {
        Dictionary(dailyScores.map { ($0.date, $0.score) }, uniquingKeysWith: { first, _ in first })
    }

    /// Per-task scores for a given date
    func taskScores(for date: String) -> [(task: TaskDefinition, value: Double, ratio: Double)] {
        guard let context = modelContext else { return [] }

        let entries: [DailyEntry] = (try? context.fetch(FetchDescriptor<DailyEntry>(
            predicate: #Predicate { $0.date == date && $0.deleted == false }
        ))) ?? []
        let entryMap = Dictionary(entries.compactMap { e in
            e.task.map { ($0.id, e) }
        }, uniquingKeysWith: { first, _ in first })

        let entryDate = dateFormatter.date(from: date) ?? Date()
        return tasks.map { task in
            let value = entryMap[task.id]?.value ?? 0
            let ratio: Double
            if task.hasPeriod, let pw = periodWindow(for: task, on: entryDate) {
                let dailyTarget = task.benchmark / Double(pw.periodDays)
                ratio = dailyTarget > 0 ? value / dailyTarget : 0
            } else {
                ratio = task.benchmark > 0 ? value / task.benchmark : 0
            }
            return (task, value, ratio)
        }
    }

    // MARK: - Period Window

    private func periodWindow(for task: TaskDefinition, on date: Date) -> (startDateStr: String, endDateStr: String, periodDays: Int)? {
        let calendar = Calendar.current
        let component: Calendar.Component
        guard let period = task.cumulativePeriod else { return nil }
        switch period {
        case "week": component = .weekOfYear
        case "month": component = .month
        case "year": component = .year
        default: return nil
        }
        guard let interval = calendar.dateInterval(of: component, for: date) else { return nil }
        let startStr = dateFormatter.string(from: interval.start)
        let endDate = calendar.date(byAdding: .day, value: -1, to: interval.end)!
        let endStr = dateFormatter.string(from: endDate)
        let days = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1
        return (startStr, endStr, days)
    }
}
