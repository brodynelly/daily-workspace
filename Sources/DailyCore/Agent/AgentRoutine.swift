import Foundation

/// When a routine runs, in the Mac's time zone.
public struct RoutineSchedule: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case daily, weekdays, weekly
        /// Every `intervalHours` hours after the last run.
        case interval
    }

    public var kind: Kind
    public var hour: Int
    public var minute: Int
    /// 1 = Sunday … 7 = Saturday, for `weekly`.
    public var weekday: Int
    public var intervalHours: Int

    public static let intervalRange = 1...24

    public init(kind: Kind = .daily, hour: Int = 8, minute: Int = 0, weekday: Int = 2, intervalHours: Int = 4) {
        self.kind = kind
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.weekday = min(max(weekday, 1), 7)
        self.intervalHours = min(max(intervalHours, Self.intervalRange.lowerBound), Self.intervalRange.upperBound)
    }

    /// The first run time strictly after `date`, or nil if the calendar cannot find one.
    public func next(after date: Date, calendar: Calendar = .current) -> Date? {
        let time = DateComponents(hour: hour, minute: minute)
        switch kind {
        case .interval:
            return date.addingTimeInterval(Double(intervalHours) * 3_600)
        case .daily:
            return calendar.nextDate(after: date, matching: time, matchingPolicy: .nextTime)
        case .weekly:
            var components = time
            components.weekday = weekday
            return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime)
        case .weekdays:
            var candidate = date
            for _ in 0..<8 {
                guard let next = calendar.nextDate(after: candidate, matching: time, matchingPolicy: .nextTime) else {
                    return nil
                }
                if !calendar.isDateInWeekend(next) { return next }
                candidate = next
            }
            return nil
        }
    }

    /// For Settings, e.g. "Weekdays at 08:00".
    public var summary: String {
        let time = String(format: "%02d:%02d", hour, minute)
        switch kind {
        case .daily: return "Daily at \(time)"
        case .weekdays: return "Weekdays at \(time)"
        case .weekly:
            let names = Calendar(identifier: .gregorian).weekdaySymbols
            return "\(names[weekday - 1])s at \(time)"
        case .interval: return intervalHours == 1 ? "Every hour" : "Every \(intervalHours) hours"
        }
    }
}

/// A question the Assistant asks itself on a schedule, created by the user. Its prompt is the user's own text,
/// never a source of consent: writes from a routine follow the same approval policy, and its edits to existing
/// text always wait for review.
public struct AgentRoutine: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var prompt: String
    public var schedule: RoutineSchedule
    public var enabled: Bool
    public let createdAt: Date
    public var lastRunAt: Date?
    /// `answered`, or why the last run failed.
    public var lastOutcome: String?
    /// The saved conversation of the last run.
    public var lastConversationID: UUID?

    public static let maxRoutines = 20

    public init(
        id: UUID = UUID(), name: String, prompt: String, schedule: RoutineSchedule = RoutineSchedule(),
        enabled: Bool = true, createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.schedule = schedule
        self.enabled = enabled
        self.createdAt = createdAt
    }

    /// When it runs next. Missed runs (the Mac asleep or the app closed) collapse into one catch-up run.
    public func nextRun(calendar: Calendar = .current) -> Date? {
        schedule.next(after: lastRunAt ?? createdAt, calendar: calendar)
    }

    public func isDue(at now: Date, calendar: Calendar = .current) -> Bool {
        guard enabled, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let next = nextRun(calendar: calendar)
        else { return false }
        return next <= now
    }
}

/// Saves routines to `routines.json`.
public struct RoutineStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() throws -> [AgentRoutine] {
        guard let data = try PrivateFile.read(url) else { return [] }
        return try PrivateFile.decoder().decode(Stored.self, from: data).routines
    }

    public func save(_ routines: [AgentRoutine]) throws {
        try PrivateFile.write(try PrivateFile.encoder().encode(Stored(version: 1, routines: routines)), to: url)
    }

    private struct Stored: Codable {
        let version: Int
        let routines: [AgentRoutine]
    }
}
