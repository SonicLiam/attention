import Foundation

/// Parses natural language date expressions in Chinese and English.
/// Returns a `Date?` from a string input.
struct NaturalDateParser: Sendable {
    private static let calendar = Calendar.current

    /// Attempts to parse a natural language date expression from the given string.
    /// Returns `nil` if no recognizable date expression is found.
    static func parse(_ input: String, relativeTo now: Date = Date()) -> Date? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Try Chinese expressions first
        if let date = parseChineseExpression(trimmed, relativeTo: now) {
            return date
        }

        // Try English expressions
        if let date = parseEnglishExpression(trimmed, relativeTo: now) {
            return date
        }

        // Try date formats
        if let date = parseDateFormat(trimmed, relativeTo: now) {
            return date
        }

        return nil
    }

    /// Detects a date expression within a longer string (e.g., a todo title).
    /// Returns the parsed date and the remaining string with the date expression removed.
    static func detectAndExtract(from input: String, relativeTo now: Date = Date()) -> (date: Date, cleanedTitle: String)? {
        let patterns: [(pattern: String, replacement: String)] = [
            // Chinese patterns
            ("今天", ""),
            ("明天", ""),
            ("后天", ""),
            ("大后天", ""),
            ("下周一", ""), ("下周二", ""), ("下周三", ""), ("下周四", ""),
            ("下周五", ""), ("下周六", ""), ("下周日", ""), ("下周天", ""),
            ("下个月", ""),
            // Chinese date with time
            ("下午\\d{1,2}点", ""),
            ("上午\\d{1,2}点", ""),
            // Chinese date formats
            ("\\d{1,2}月\\d{1,2}[日号]", ""),
            // English patterns
            ("\\btoday\\b", ""),
            ("\\btomorrow\\b", ""),
            ("\\bthe day after tomorrow\\b", ""),
            ("\\bnext\\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\\b", ""),
            ("\\bnext\\s+week\\b", ""),
            ("\\bnext\\s+month\\b", ""),
            ("\\bin\\s+\\d+\\s+days?\\b", ""),
            ("\\b\\d{1,2}(am|pm)\\b", ""),
            ("\\b\\d{1,2}:\\d{2}\\b", ""),
            // Date formats
            ("\\b(january|february|march|april|may|june|july|august|september|october|november|december)\\s+\\d{1,2}\\b", ""),
            ("\\b\\d{1,2}/\\d{1,2}\\b", ""),
        ]

        for (pattern, _) in patterns {
            if let range = input.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let matchedText = String(input[range])
                if let date = parse(matchedText, relativeTo: now) {
                    var cleaned = input
                    cleaned.removeSubrange(range)
                    cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Remove trailing/leading punctuation artifacts
                    cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " ,，、"))
                    if !cleaned.isEmpty {
                        return (date: date, cleanedTitle: cleaned)
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Chinese Expressions

    private static func parseChineseExpression(_ input: String, relativeTo now: Date) -> Date? {
        let startOfDay = calendar.startOfDay(for: now)

        switch input {
        case "今天":
            return startOfDay
        case "明天":
            return calendar.date(byAdding: .day, value: 1, to: startOfDay)
        case "后天":
            return calendar.date(byAdding: .day, value: 2, to: startOfDay)
        case "大后天":
            return calendar.date(byAdding: .day, value: 3, to: startOfDay)
        case "下个月":
            return calendar.date(byAdding: .month, value: 1, to: startOfDay)
        default:
            break
        }

        // 下周X
        let weekdayMap: [String: Int] = [
            "下周一": 2, "下周二": 3, "下周三": 4, "下周四": 5,
            "下周五": 6, "下周六": 7, "下周日": 1, "下周天": 1
        ]
        if let targetWeekday = weekdayMap[input] {
            return nextWeekday(targetWeekday, from: now)
        }

        // X月X日 / X月X号
        if let match = input.range(of: #"(\d{1,2})月(\d{1,2})[日号]?"#, options: .regularExpression) {
            let matched = String(input[match])
            let digits = matched.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
            if digits.count >= 2, let month = Int(digits[0]), let day = Int(digits[1]) {
                let year = calendar.component(.year, from: now)
                var components = DateComponents()
                components.year = year
                components.month = month
                components.day = day
                if let date = calendar.date(from: components) {
                    // If date is in the past, use next year
                    if date < startOfDay {
                        components.year = year + 1
                        return calendar.date(from: components)
                    }
                    return date
                }
            }
        }

        // 下午X点 / 上午X点
        if let match = input.range(of: #"(上午|下午)(\d{1,2})点"#, options: .regularExpression) {
            let matched = String(input[match])
            let isPM = matched.contains("下午")
            let digits = matched.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
            if let hourStr = digits.first, var hour = Int(hourStr) {
                if isPM && hour < 12 { hour += 12 }
                if !isPM && hour == 12 { hour = 0 }
                var components = calendar.dateComponents([.year, .month, .day], from: now)
                components.hour = hour
                components.minute = 0
                return calendar.date(from: components)
            }
        }

        return nil
    }

    // MARK: - English Expressions

    private static func parseEnglishExpression(_ input: String, relativeTo now: Date) -> Date? {
        let startOfDay = calendar.startOfDay(for: now)

        switch input {
        case "today":
            return startOfDay
        case "tomorrow":
            return calendar.date(byAdding: .day, value: 1, to: startOfDay)
        case "the day after tomorrow":
            return calendar.date(byAdding: .day, value: 2, to: startOfDay)
        case "next week":
            return calendar.date(byAdding: .weekOfYear, value: 1, to: startOfDay)
        case "next month":
            return calendar.date(byAdding: .month, value: 1, to: startOfDay)
        default:
            break
        }

        // "next monday", "next tuesday", etc.
        let englishWeekdays: [String: Int] = [
            "next monday": 2, "next tuesday": 3, "next wednesday": 4,
            "next thursday": 5, "next friday": 6, "next saturday": 7, "next sunday": 1
        ]
        if let targetWeekday = englishWeekdays[input] {
            return nextWeekday(targetWeekday, from: now)
        }

        // "in X days"
        if let match = input.range(of: #"in\s+(\d+)\s+days?"#, options: .regularExpression) {
            let matched = String(input[match])
            let digits = matched.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
            if let daysStr = digits.first, let days = Int(daysStr) {
                return calendar.date(byAdding: .day, value: days, to: startOfDay)
            }
        }

        // "Xam" / "Xpm"
        if let match = input.range(of: #"(\d{1,2})(am|pm)"#, options: .regularExpression) {
            let matched = String(input[match])
            let isPM = matched.hasSuffix("pm")
            let digits = matched.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
            if let hourStr = digits.first, var hour = Int(hourStr) {
                if isPM && hour < 12 { hour += 12 }
                if !isPM && hour == 12 { hour = 0 }
                var components = calendar.dateComponents([.year, .month, .day], from: now)
                components.hour = hour
                components.minute = 0
                return calendar.date(from: components)
            }
        }

        // "HH:MM"
        if let match = input.range(of: #"(\d{1,2}):(\d{2})"#, options: .regularExpression) {
            let matched = String(input[match])
            let parts = matched.split(separator: ":")
            if parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) {
                var components = calendar.dateComponents([.year, .month, .day], from: now)
                components.hour = hour
                components.minute = minute
                return calendar.date(from: components)
            }
        }

        // "March 15", "January 1", etc.
        let monthNames: [String: Int] = [
            "january": 1, "february": 2, "march": 3, "april": 4,
            "may": 5, "june": 6, "july": 7, "august": 8,
            "september": 9, "october": 10, "november": 11, "december": 12
        ]
        for (monthName, monthNum) in monthNames {
            let pattern = "\(monthName)\\s+(\\d{1,2})"
            if let match = input.range(of: pattern, options: .regularExpression) {
                let matched = String(input[match])
                let digits = matched.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
                if let dayStr = digits.first, let day = Int(dayStr) {
                    let year = calendar.component(.year, from: now)
                    var components = DateComponents()
                    components.year = year
                    components.month = monthNum
                    components.day = day
                    if let date = calendar.date(from: components) {
                        if date < startOfDay {
                            components.year = year + 1
                            return calendar.date(from: components)
                        }
                        return date
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Date Formats

    private static func parseDateFormat(_ input: String, relativeTo now: Date) -> Date? {
        let startOfDay = calendar.startOfDay(for: now)

        // M/D format
        if let match = input.range(of: #"^(\d{1,2})/(\d{1,2})$"#, options: .regularExpression) {
            let matched = String(input[match])
            let parts = matched.split(separator: "/")
            if parts.count == 2, let month = Int(parts[0]), let day = Int(parts[1]) {
                let year = calendar.component(.year, from: now)
                var components = DateComponents()
                components.year = year
                components.month = month
                components.day = day
                if let date = calendar.date(from: components) {
                    if date < startOfDay {
                        components.year = year + 1
                        return calendar.date(from: components)
                    }
                    return date
                }
            }
        }

        return nil
    }

    // MARK: - Helpers

    private static func nextWeekday(_ weekday: Int, from date: Date) -> Date? {
        let current = calendar.component(.weekday, from: date)
        var daysToAdd = weekday - current
        if daysToAdd <= 0 { daysToAdd += 7 }
        return calendar.date(byAdding: .day, value: daysToAdd, to: calendar.startOfDay(for: date))
    }
}
