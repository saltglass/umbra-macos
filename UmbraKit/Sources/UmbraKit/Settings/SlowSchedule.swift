import Foundation

/// Umbra writes the slow-mode schedule's times as "HH:MM" text (local
/// time, 24 hours). The Speed page uses the system's time pickers, which
/// work in dates; this turns one into the other.
public enum ClockTime {
  /// Hour and minute from "HH:MM"; nil when it isn't that.
  public static func parse(_ text: String) -> (hour: Int, minute: Int)? {
    let parts = text.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
      (0..<24).contains(hour), (0..<60).contains(minute)
    else { return nil }
    return (hour, minute)
  }

  /// "07:05".
  public static func text(hour: Int, minute: Int) -> String {
    String(format: "%02d:%02d", hour, minute)
  }

  /// A date at that time of day, on `day` (only the time matters to a
  /// time picker). Nil when `text` isn't "HH:MM".
  public static func date(
    from text: String, on day: Date = Date(), calendar: Calendar = .current
  ) -> Date? {
    guard let time = parse(text) else { return nil }
    return calendar.date(
      bySettingHour: time.hour, minute: time.minute, second: 0, of: day,
      matchingPolicy: .nextTime)
  }

  /// "HH:MM" for the time of day of `date`.
  public static func text(from date: Date, calendar: Calendar = .current) -> String {
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    return text(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
  }

  /// The time as the Mac writes times ("22:00", or "10:00 PM"), to match
  /// what the time pickers show. Falls back to the text itself.
  public static func display(
    _ text: String, calendar: Calendar = .current, locale: Locale = .current
  ) -> String {
    guard let date = date(from: text, calendar: calendar) else { return text }
    return date.formatted(
      Date.FormatStyle(
        date: .omitted, time: .shortened, locale: locale, calendar: calendar,
        timeZone: calendar.timeZone))
  }

  /// Minutes since midnight, for comparing two times.
  static func minutes(_ text: String) -> Int? {
    parse(text).map { $0.hour * 60 + $0.minute }
  }
}

/// The days of the slow-mode schedule: Umbra numbers them 0 (Sunday) to
/// 6 (Saturday), and the Mac's own weekday names use the same order.
public enum ScheduleDays {
  /// The order the page lists them in: Monday first, as Umbra's web page does.
  public static let displayOrder = [1, 2, 3, 4, 5, 6, 0]

  /// `days` with `day` added or taken away, in Umbra's order, no repeats.
  public static func setting(_ day: Int, on: Bool, in days: [Int]) -> [Int] {
    var set = Set(days)
    if on { set.insert(day) } else { set.remove(day) }
    return set.sorted()
  }

  /// "Monday" (a day number from 0 to 6).
  public static func name(of day: Int, calendar: Calendar = .current) -> String {
    calendar.weekdaySymbols[(day % 7 + 7) % 7]
  }

  /// "Mon".
  public static func shortName(of day: Int, calendar: Calendar = .current) -> String {
    calendar.shortWeekdaySymbols[(day % 7 + 7) % 7]
  }

  /// "every day", "Monday to Friday", "Saturday and Sunday",
  /// "Monday, Wednesday and Friday" (Umbra's web page words it the same).
  public static func words(_ days: [Int], calendar: Calendar = .current) -> String {
    let chosen = displayOrder.filter { days.contains($0) }
    if chosen.count == 7 { return "every day" }
    let places = chosen.map { displayOrder.firstIndex(of: $0) ?? 0 }
    let names = chosen.map { name(of: $0, calendar: calendar) }
    let oneRun = places.count > 2 && zip(places, places.dropFirst()).allSatisfy { $1 == $0 + 1 }
    if oneRun, let first = names.first, let last = names.last { return "\(first) to \(last)" }
    switch names.count {
    case 0: return "no days"
    case 1: return names[0]
    default: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }
  }
}

/// The sentence under the schedule saying when slow mode will run.
public enum ScheduleSummary {
  public static func text(
    days: [Int], from: String, to: String, calendar: Calendar = .current,
    locale: Locale = .current
  ) -> String {
    if days.isEmpty { return "Choose at least one day." }
    let when = ScheduleDays.words(days, calendar: calendar)
    let start = ClockTime.display(from, calendar: calendar, locale: locale)
    let end = ClockTime.display(to, calendar: calendar, locale: locale)
    let line: String
    if let a = ClockTime.minutes(from), let b = ClockTime.minutes(to), a == b {
      // Umbra treats the same time twice as the whole day.
      line = "Slow mode runs \(when), all day."
    } else if let a = ClockTime.minutes(from), let b = ClockTime.minutes(to), b < a {
      // Umbra: an end earlier than the start runs past midnight and belongs
      // to the day it starts on.
      line =
        "Slow mode runs \(when), \(start) to \(end) the next morning (past midnight, on each "
        + "day it starts)."
    } else {
      line = "Slow mode runs \(when), \(start) to \(end)."
    }
    return line + " At all other times Umbra uses the normal limits."
  }
}
