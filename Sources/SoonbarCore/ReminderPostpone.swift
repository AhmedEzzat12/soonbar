import Foundation

/// "Remind me later" choices for a reminder, and the due date each one moves it to.
public enum ReminderPostpone: CaseIterable, Sendable {
    case inAnHour
    case thisEvening
    case tomorrow
    case nextWeek

    /// "This evening" means this hour, and is offered only while it is still at least an hour away.
    static let eveningHour = 18

    public var title: String {
        switch self {
        case .inAnHour: "In 1 Hour"
        case .thisEvening: "This Evening"
        case .tomorrow: "Tomorrow"
        case .nextWeek: "Next Week"
        }
    }

    public static func options(now: Date, calendar: Calendar) -> [ReminderPostpone] {
        allCases.filter { $0 != .thisEvening || calendar.component(.hour, from: now) < eveningHour - 1 }
    }

    /// The new due date, counted from today (an overdue reminder moves forward from now, not from its old date).
    /// Tomorrow and Next Week keep the reminder's time of day, or stay date-only.
    public func newDue(for reminder: ReminderItem, now: Date, calendar: Calendar) -> (date: Date, hasTime: Bool) {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .inAnHour:
            let step: TimeInterval = 5 * 60
            let target = now.addingTimeInterval(3600)
            return (Date(timeIntervalSinceReferenceDate: (target.timeIntervalSinceReferenceDate / step).rounded(.up) * step), true)
        case .thisEvening:
            return (calendar.date(bySettingHour: Self.eveningHour, minute: 0, second: 0, of: today) ?? now, true)
        case .tomorrow:
            return keepingTime(of: reminder, on: calendar.date(byAdding: .day, value: 1, to: today) ?? today, calendar: calendar)
        case .nextWeek:
            let monday = calendar.nextDate(after: today, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime) ?? today
            return keepingTime(of: reminder, on: monday, calendar: calendar)
        }
    }

    private func keepingTime(of reminder: ReminderItem, on day: Date, calendar: Calendar) -> (date: Date, hasTime: Bool) {
        guard reminder.hasTime else { return (day, false) }
        let time = calendar.dateComponents([.hour, .minute], from: reminder.due)
        let date = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: day) ?? day
        return (date, true)
    }
}
