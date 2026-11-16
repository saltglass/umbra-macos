import Foundation

/// How numbers and dates read in the list, copied rule for rule from Umbra's
/// web page (`web/src/lib/format.ts`) so the Mac app and the web page show
/// the same figures:
///
/// - sizes with one decimal ("31.0 GB", "860 KB"), counted in 1024s as
///   qBittorrent does (so a 5 MB/s limit shows as 5 MB/s);
/// - short times left ("41m", "2h 05m");
/// - dates relative to today ("Today 09:12", "Yesterday", "26 Oct").
///
/// A dash stands for "nothing to show".
public enum Format {
  /// The "nothing to show" mark.
  public static let dash = "—"

  private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]

  // MARK: Sizes and speeds

  /// Bytes as "31.0 GB" (1 KB = 1024 bytes).
  public static func bytes(_ n: Int64) -> String { bytes(Double(n)) }

  /// Bytes as "31.0 GB"; nothing, a negative or a non-number is a dash.
  public static func bytes(_ n: Double?) -> String {
    guard let n, n.isFinite, n >= 0 else { return dash }
    if n < 1000 { return "\(Int64(jsRound(n))) B" }
    var value = n
    var unit = 0
    while value >= 999.95 && unit < units.count - 1 {
      value /= 1024
      unit += 1
    }
    // KB, and anything from 100 up, without a decimal ("860 KB", "734 MB");
    // the rest with one ("31.0 GB"), so a value fits its column.
    if unit == 1 || value >= 99.95 { return "\(Int64(jsRound(value))) \(units[unit])" }
    return "\(fixed(value, digits: 1)) \(units[unit])"
  }

  /// Bytes per second as "8.4 MB/s"; zero (or nothing) is `zero`, a dash by default.
  public static func speed(_ n: Int64?, zero: String = dash) -> String {
    guard let n, n > 0 else { return zero }
    return "\(bytes(n))/s"
  }

  // MARK: Times

  /// Seconds left as "41m", "2h 05m", "3d 4h"; unknown is a dash, 100 days or more "∞".
  public static func eta(_ seconds: Int64?) -> String {
    guard let seconds else { return dash }
    return eta(Double(seconds))
  }

  static func eta(_ secs: Double) -> String {
    guard secs.isFinite, secs >= 0 else { return dash }
    if secs < 60 { return "\(Int64(max(1, jsRound(secs))))s" }
    let minutes = Int64(jsRound(secs / 60))
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    if hours < 24 {
      let rest = minutes % 60
      return "\(hours)h \(rest < 10 ? "0" : "")\(rest)m"
    }
    let days = hours / 24
    return days < 100 ? "\(days)d \(hours % 24)h" : "∞"
  }

  /// A length of time as "3d 4h", "2h 05m", "41m", "12s" (seed time); none is a dash.
  public static func duration(_ seconds: Int64?) -> String {
    guard let seconds, seconds != 0 else { return dash }
    if seconds < 60 { return "\(seconds)s" }
    return eta(Double(seconds))
  }

  // MARK: Ratios, percentages, counts

  /// A share ratio with two decimals ("2.41"); unknown is "∞".
  public static func ratio(_ r: Double?) -> String {
    guard let r, r.isFinite else { return "∞" }
    return fixed(r, digits: 2)
  }

  /// 0.341 as "34%", 1 as "100%". Always rounded down, so "100%" means done.
  public static func percent(_ p: Double) -> String {
    "\(Int(((min(max(p, 0), 1)) * 100).rounded(.down)))%"
  }

  /// "1,204": a count with the person's thousands separators.
  public static func count(_ n: Int, locale: Locale = .current) -> String {
    n.formatted(.number.locale(locale))
  }

  // MARK: Dates

  /// The calendar, time zone and language dates are written in. Tests fix
  /// them so results don't depend on the machine running the tests.
  public struct DateStyle: Sendable, Equatable {
    public var locale: Locale
    public var timeZone: TimeZone
    public var calendar: Calendar

    public init(locale: Locale, timeZone: TimeZone) {
      self.locale = locale
      self.timeZone = timeZone
      var calendar = Calendar(identifier: .gregorian)
      calendar.locale = locale
      calendar.timeZone = timeZone
      self.calendar = calendar
    }

    /// The person's own settings.
    public static var current: DateStyle { DateStyle(locale: .current, timeZone: .current) }

    var base: Date.FormatStyle {
      Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
    }
  }

  /// A date in the list: "Today 09:12", "Yesterday", "26 Oct", "26 Oct 2025".
  /// (The day and month come in the person's own order: "Oct 26" in the US.)
  public static func shortDate(_ date: Date?, now: Date, style: DateStyle = .current) -> String {
    guard let date else { return dash }
    let calendar = style.calendar
    // Whole days between the two midnights, rounded as the web page does,
    // so a day with a clock change still counts as one.
    let gap = calendar.startOfDay(for: now).timeIntervalSince(calendar.startOfDay(for: date))
    let days = jsRound(gap / 86_400)
    if days == 0 { return "Today \(date.formatted(style.base.hour().minute()))" }
    if days == 1 { return "Yesterday" }
    let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
    let dayMonth = style.base.day().month(.abbreviated)
    return date.formatted(sameYear ? dayMonth : dayMonth.year())
  }

  /// A date in full, for a torrent's details: "28 Oct 2026, 09:12".
  public static func longDate(_ date: Date?, style: DateStyle = .current) -> String {
    guard let date else { return dash }
    let day = date.formatted(style.base.day().month(.abbreviated).year())
    return "\(day), \(date.formatted(style.base.hour().minute()))"
  }

  // MARK: JavaScript's arithmetic

  /// `Math.round`: halves go up (towards positive infinity).
  static func jsRound(_ x: Double) -> Double {
    let floor = x.rounded(.down)
    return x - floor >= 0.5 ? floor + 1 : floor
  }

  /// `Number.toFixed`: `digits` decimals. It agrees with C's `%f` except on
  /// an exact halfway value (such as 0.25 to one decimal), which `%f`
  /// rounds to even ("0.2") and JavaScript rounds up ("0.3").
  static func fixed(_ x: Double, digits: Int) -> String {
    let scale = pow(10, Double(digits))
    let scaled = abs(x) * scale
    // Only an exact halfway value that multiplied without any rounding
    // counts; anything else `%f` already gets right.
    if scaled - scaled.rounded(.down) == 0.5, scaled / scale == abs(x) {
      let up = scaled.rounded(.up) / scale
      return String(format: "%.\(digits)f", x < 0 ? -up : up)
    }
    return String(format: "%.\(digits)f", x)
  }
}
