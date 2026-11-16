import Foundation
import UmbraAPI

/// How serious a log line is. Umbra keeps Info and above, so these are all
/// the levels there are.
public enum LogLevel: String, Sendable, CaseIterable, Comparable {
  case info, warning, error

  /// The word shown in the Level column.
  public var title: String {
    switch self {
    case .info: "Info"
    case .warning: "Warning"
    case .error: "Error"
    }
  }

  /// Warnings are orange and errors red; Info stays quiet.
  public var role: ColorRole {
    switch self {
    case .info: .secondary
    case .warning: .orange
    case .error: .red
    }
  }

  private var rank: Int {
    switch self {
    case .info: 0
    case .warning: 1
    case .error: 2
    }
  }

  public static func < (a: LogLevel, b: LogLevel) -> Bool { a.rank < b.rank }
}

/// Which levels the window shows (the toolbar's picker).
public enum LogLevelFilter: String, Sendable, CaseIterable, Identifiable {
  case all, warningsAndErrors, errors

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .all: "All Levels"
    case .warningsAndErrors: "Warnings and Errors"
    case .errors: "Errors Only"
    }
  }

  /// The value Umbra's `levels` parameter takes; nil means all.
  var levelsQuery: String? {
    switch self {
    case .all: nil
    case .warningsAndErrors: "warning,error"
    case .errors: "error"
    }
  }

  func includes(_ level: LogLevel) -> Bool {
    switch self {
    case .all: true
    case .warningsAndErrors: level >= .warning
    case .errors: level == .error
    }
  }
}

/// One line of Umbra's log, ready to show.
///
/// The words are Umbra's own. The one thing done to them: if the text
/// holds the app's current credential, it is replaced with "•••".
public struct LogLine: Identifiable, Equatable, Sendable {
  /// Umbra's own number for the line (it grows with each line written).
  public let id: Int64
  public let time: Date
  public let level: LogLevel
  /// The torrent the line is about, or "Umbra".
  public let source: String
  /// Umbra's message, followed by its other details as `key=value`.
  public let text: String

  public init(id: Int64, time: Date, level: LogLevel, source: String, text: String) {
    self.id = id
    self.time = time
    self.level = level
    self.source = source
    self.text = text
  }

  init(_ entry: Components.Schemas.LogEntry, hiding secret: String) {
    var text = entry.message
    if !entry.attrs.isEmpty {
      text += "  " + entry.attrs.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
    }
    self.init(
      id: entry.seq, time: entry.time, level: LogLevel(rawValue: entry.level.rawValue) ?? .info,
      source: LogRedaction.hide(secret, in: entry.source),
      text: LogRedaction.hide(secret, in: text))
  }

  /// The time of day, as the Time column shows it.
  public var timeOfDay: String {
    time.formatted(.dateTime.hour().minute().second())
  }

  /// The whole line as plain text, for copying and for the tooltip.
  public func plainText(timeZone: TimeZone = .current) -> String {
    "\(LogRedaction.stamp(time, timeZone: timeZone))  \(level.title)  \(source)  \(text)"
  }

  /// Whether the search words are in the line (any case).
  func matches(_ search: String) -> Bool {
    text.range(of: search, options: .caseInsensitive) != nil
      || source.range(of: search, options: .caseInsensitive) != nil
  }
}

/// Hiding the credential, and writing times for copied text.
enum LogRedaction {
  static let mask = "•••"

  /// `text` with every copy of `secret` replaced. An empty secret hides nothing.
  static func hide(_ secret: String, in text: String) -> String {
    guard !secret.isEmpty else { return text }
    return text.replacingOccurrences(of: secret, with: mask)
  }

  /// "2026-11-14 14:30:05" in the given time zone.
  static func stamp(_ date: Date, timeZone: TimeZone) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    return String(
      format: "%04d-%02d-%02d %02d:%02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0,
      c.minute ?? 0, c.second ?? 0)
  }
}
