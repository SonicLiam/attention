import Foundation
import SwiftData

enum RecurrenceFrequency: String, Codable, CaseIterable {
    case daily
    case weekly
    case biweekly
    case monthly
    case yearly
    case custom

    var label: String {
        switch self {
        case .daily: "Every Day"
        case .weekly: "Every Week"
        case .biweekly: "Every 2 Weeks"
        case .monthly: "Every Month"
        case .yearly: "Every Year"
        case .custom: "Custom"
        }
    }
}

@Model
final class Recurrence {
    @Attribute(.unique) var id: UUID
    var frequency: RecurrenceFrequency
    var interval: Int  // e.g., every 3 days
    var daysOfWeek: [Int]?  // 1=Sunday ... 7=Saturday
    var dayOfMonth: Int?
    var endDate: Date?

    @Relationship(inverse: \Todo.recurrence) var todo: Todo?

    init(
        frequency: RecurrenceFrequency,
        interval: Int = 1,
        daysOfWeek: [Int]? = nil,
        dayOfMonth: Int? = nil,
        endDate: Date? = nil
    ) {
        self.id = UUID()
        self.frequency = frequency
        self.interval = interval
        self.daysOfWeek = daysOfWeek
        self.dayOfMonth = dayOfMonth
        self.endDate = endDate
    }

    /// Calculate the next occurrence date from a given date
    func nextDate(after date: Date) -> Date? {
        let calendar = Calendar.current

        if let endDate, date >= endDate {
            return nil
        }

        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: interval, to: date)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: interval, to: date)
        case .biweekly:
            return calendar.date(byAdding: .weekOfYear, value: 2, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: interval, to: date)
        case .yearly:
            return calendar.date(byAdding: .year, value: interval, to: date)
        case .custom:
            return calendar.date(byAdding: .day, value: interval, to: date)
        }
    }
}
