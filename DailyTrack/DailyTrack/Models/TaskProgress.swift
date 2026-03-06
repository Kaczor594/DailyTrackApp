import Foundation

/// Combined view of a task definition with its entry for a specific day.
/// Used by the UI to display task rows with progress.
struct TaskProgress: Identifiable {
    let task: TaskDefinition
    var entry: DailyEntry
    var cumulativeTotal: Double?    // Only set for cumulative tasks
    var periodDays: Int?            // Only set for period-cumulative tasks

    var id: String { task.id }

    /// Completion ratio for today's entry
    var dailyRatio: Double {
        entry.completionRatio(benchmark: task.benchmark)
    }

    /// Scoring ratio used for daily score and badge display.
    /// For period-cumulative tasks: entry.value / (benchmark / periodDays).
    /// Otherwise falls back to dailyRatio.
    var scoringRatio: Double {
        if task.hasPeriod, let pd = periodDays, pd > 0, task.benchmark > 0 {
            let dailyTarget = task.benchmark / Double(pd)
            return dailyTarget > 0 ? entry.value / dailyTarget : 0
        }
        return dailyRatio
    }

    /// Formatted display of daily progress
    var dailyProgressText: String {
        if task.isCheckbox {
            return entry.value > 0 ? String(localized: "Done") : String(localized: "Not done")
        }
        let valueStr = formatNumber(entry.value)
        let benchStr = formatNumber(task.benchmark)
        return "\(valueStr) / \(benchStr) \(task.unit)"
    }

    /// Period progress text, e.g. "7/10 this week"
    var periodProgressText: String? {
        guard task.hasPeriod, let total = cumulativeTotal else { return nil }
        let totalStr = formatNumber(total)
        let benchStr = formatNumber(task.benchmark)
        let periodLabel: String
        switch task.cumulativePeriod ?? "none" {
        case "week": periodLabel = String(localized: "this week")
        case "month": periodLabel = String(localized: "this month")
        case "year": periodLabel = String(localized: "this year")
        default: return nil
        }
        return "\(totalStr)/\(benchStr) \(periodLabel)"
    }

    /// Cumulative progress as percentage toward benchmark (for cumulative tasks)
    var cumulativeRatio: Double? {
        guard task.isCumulative, let total = cumulativeTotal else { return nil }
        guard task.benchmark > 0 else { return 0 }
        return total / task.benchmark
    }

    private func formatNumber(_ n: Double) -> String {
        if n == n.rounded() {
            return String(Int(n))
        }
        return String(format: "%.1f", n)
    }
}
