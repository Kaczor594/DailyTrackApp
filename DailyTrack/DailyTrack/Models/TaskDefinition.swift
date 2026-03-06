import Foundation
import SwiftData

/// A task that can be tracked daily or cumulatively.
@Model
final class TaskDefinition {
    var id: String
    var name: String
    var benchmark: Double
    var unit: String
    var weight: Double
    var isCumulative: Bool
    var cumulativePeriod: String?
    var isCheckbox: Bool
    var sortOrder: Int
    var isActive: Bool
    var createdAt: String
    var updatedAt: String
    var deleted: Bool

    /// Whether this cumulative task has a period (week/month/year) set
    var hasPeriod: Bool {
        guard isCumulative, let period = cumulativePeriod else { return false }
        return period != "none"
    }

    @Relationship(deleteRule: .cascade, inverse: \DailyEntry.task)
    var entries: [DailyEntry]?

    init(
        id: String = UUID().uuidString,
        name: String,
        benchmark: Double = 1.0,
        unit: String = "",
        weight: Double = 1.0,
        isCumulative: Bool = false,
        cumulativePeriod: String? = nil,
        isCheckbox: Bool = false,
        sortOrder: Int = 0,
        isActive: Bool = true,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        updatedAt: String = ISO8601DateFormatter().string(from: Date()),
        deleted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.benchmark = benchmark
        self.unit = unit
        self.weight = weight
        self.isCumulative = isCumulative
        self.cumulativePeriod = cumulativePeriod
        self.isCheckbox = isCheckbox
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deleted = deleted
    }

    func markUpdated() {
        self.updatedAt = ISO8601DateFormatter().string(from: Date())
    }
}

/// Codable version for JSON export/import and sync.
struct CodableTaskDefinition: Codable {
    let id: String
    var name: String
    var benchmark: Double
    var unit: String
    var weight: Double
    var isCumulative: Bool
    var cumulativePeriod: String
    var isCheckbox: Bool
    var sortOrder: Int
    var isActive: Bool
    var createdAt: String
    var updatedAt: String
    var deleted: Bool

    // Keys matching the Cloudflare D1 column names
    enum CodingKeys: String, CodingKey {
        case id, name, benchmark, unit, weight
        case isCumulative = "is_cumulative"
        case cumulativePeriod = "cumulative_period"
        case isCheckbox = "is_checkbox"
        case sortOrder = "sort_order"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deleted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        benchmark = try c.decode(Double.self, forKey: .benchmark)
        unit = try c.decode(String.self, forKey: .unit)
        weight = try c.decode(Double.self, forKey: .weight)
        isCumulative = (try c.decode(Int.self, forKey: .isCumulative)) != 0
        cumulativePeriod = (try? c.decode(String.self, forKey: .cumulativePeriod)) ?? "none"
        isCheckbox = (try c.decode(Int.self, forKey: .isCheckbox)) != 0
        sortOrder = try c.decode(Int.self, forKey: .sortOrder)
        isActive = (try c.decode(Int.self, forKey: .isActive)) != 0
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        deleted = (try c.decode(Int.self, forKey: .deleted)) != 0
    }

    init(from task: TaskDefinition) {
        self.id = task.id
        self.name = task.name
        self.benchmark = task.benchmark
        self.unit = task.unit
        self.weight = task.weight
        self.isCumulative = task.isCumulative
        self.cumulativePeriod = task.cumulativePeriod ?? "none"
        self.isCheckbox = task.isCheckbox
        self.sortOrder = task.sortOrder
        self.isActive = task.isActive
        self.createdAt = task.createdAt
        self.updatedAt = task.updatedAt
        self.deleted = task.deleted
    }
}
