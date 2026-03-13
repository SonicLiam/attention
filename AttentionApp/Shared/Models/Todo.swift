import Foundation
import SwiftData

// MARK: - Reminder Offset

/// Reminder offset options for scheduling notifications relative to a todo's date
enum ReminderOffset: String, Codable, CaseIterable, Sendable {
    case atTime = "at_time"
    case fifteenMinBefore = "15min_before"
    case oneHourBefore = "1hr_before"
    case oneDayBefore = "1day_before"

    var label: String {
        switch self {
        case .atTime: "At time"
        case .fifteenMinBefore: "15 minutes before"
        case .oneHourBefore: "1 hour before"
        case .oneDayBefore: "1 day before"
        }
    }

    var timeInterval: TimeInterval {
        switch self {
        case .atTime: 0
        case .fifteenMinBefore: -15 * 60
        case .oneHourBefore: -3600
        case .oneDayBefore: -86400
        }
    }
}

// MARK: - Todo Status

enum TodoStatus: String, Codable, CaseIterable {
    case inbox
    case active
    case completed
    case cancelled
}

// MARK: - Priority

enum Priority: Int, Codable, CaseIterable, Comparable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3

    static func < (lhs: Priority, rhs: Priority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

// MARK: - Todo Model

@Model
final class Todo {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var status: TodoStatus
    var priority: Priority
    var createdAt: Date
    var modifiedAt: Date
    var completedAt: Date?
    var scheduledDate: Date?
    var deadline: Date?
    var sortOrder: Int
    var headingId: UUID?
    var reminderDate: Date?
    var reminderOffset: ReminderOffset?

    // Relationships
    @Relationship(inverse: \Project.todos) var project: Project?
    @Relationship(inverse: \Area.todos) var area: Area?
    @Relationship var tags: [Tag]
    @Relationship(deleteRule: .cascade) var checklist: [ChecklistItem]
    @Relationship(deleteRule: .cascade) var recurrence: Recurrence?

    // Sync metadata
    var syncId: String?
    var lastSyncedAt: Date?
    var isDirty: Bool

    init(
        title: String,
        notes: String = "",
        status: TodoStatus = .inbox,
        priority: Priority = .none,
        scheduledDate: Date? = nil,
        deadline: Date? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.status = status
        self.priority = priority
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.scheduledDate = scheduledDate
        self.deadline = deadline
        self.sortOrder = 0
        self.tags = []
        self.checklist = []
        self.isDirty = true
    }

    // MARK: - Computed Properties

    var isCompleted: Bool { status == .completed }
    var isCancelled: Bool { status == .cancelled }
    var isActive: Bool { status == .active || status == .inbox }

    var isOverdue: Bool {
        guard let deadline else { return false }
        return !isCompleted && deadline < Date()
    }

    var isToday: Bool {
        guard let scheduledDate else { return false }
        return Calendar.current.isDateInToday(scheduledDate)
    }

    // MARK: - Actions

    func complete() {
        status = .completed
        completedAt = Date()
        modifiedAt = Date()
        isDirty = true
    }

    func uncomplete() {
        status = .active
        completedAt = nil
        modifiedAt = Date()
        isDirty = true
    }

    func cancel() {
        status = .cancelled
        modifiedAt = Date()
        isDirty = true
    }

    func moveToInbox() {
        status = .inbox
        scheduledDate = nil
        project = nil
        modifiedAt = Date()
        isDirty = true
    }

    func scheduleForToday() {
        scheduledDate = Calendar.current.startOfDay(for: Date())
        status = .active
        modifiedAt = Date()
        isDirty = true
    }

    func scheduleFor(_ date: Date) {
        scheduledDate = date
        status = .active
        modifiedAt = Date()
        isDirty = true
    }

    func moveToSomeday() {
        scheduledDate = nil
        status = .active
        modifiedAt = Date()
        isDirty = true
    }

    func markDirty() {
        modifiedAt = Date()
        isDirty = true
    }
}
