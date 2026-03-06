import Foundation
import SwiftData

/// A single entry recording progress on a task for a specific day.
@Model
final class DailyEntry {
    var id: String
    var date: String           // "yyyy-MM-dd" format
    var value: Double
    var notes: String?
    var updatedAt: String
    var deleted: Bool

    var task: TaskDefinition?

    init(
        id: String = UUID().uuidString,
        task: TaskDefinition? = nil,
        date: String,
        value: Double = 0.0,
        notes: String? = nil,
        updatedAt: String = ISO8601DateFormatter().string(from: Date()),
        deleted: Bool = false
    ) {
        self.id = id
        self.task = task
        self.date = date
        self.value = value
        self.notes = notes
        self.updatedAt = updatedAt
        self.deleted = deleted
    }

    /// Completion ratio for this entry given a benchmark.
    func completionRatio(benchmark: Double) -> Double {
        guard benchmark > 0 else { return 0 }
        return value / benchmark
    }

    func markUpdated() {
        self.updatedAt = ISO8601DateFormatter().string(from: Date())
    }
}

/// Codable version for sync.
struct CodableDailyEntry: Codable {
    let id: String
    let taskId: String
    let date: String
    var value: Double
    var notes: String?
    var createdAt: String
    var updatedAt: String
    var deleted: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case date, value, notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deleted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        taskId = try c.decode(String.self, forKey: .taskId)
        date = try c.decode(String.self, forKey: .date)
        value = try c.decode(Double.self, forKey: .value)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        deleted = (try c.decode(Int.self, forKey: .deleted)) != 0
    }

    init(from entry: DailyEntry) {
        self.id = entry.id
        self.taskId = entry.task?.id ?? ""
        self.date = entry.date
        self.value = entry.value
        self.notes = entry.notes
        self.createdAt = entry.updatedAt // use updatedAt as fallback
        self.updatedAt = entry.updatedAt
        self.deleted = entry.deleted
    }
}
