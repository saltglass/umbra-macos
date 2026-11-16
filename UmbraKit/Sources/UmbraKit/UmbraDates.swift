import Foundation
import OpenAPIRuntime

/// Reads and writes times the way Umbra does.
///
/// Umbra is written in Go, which writes times to the nanosecond when there is
/// a fraction ("2026-11-12T10:00:00.123456789Z") and with none when the time
/// is a whole second ("2026-11-12T10:00:00Z"). Foundation's ISO 8601 readers
/// each accept only one of those forms, so this tries both. Both the live
/// feed's reader (`FeedJSON`) and the generated client (`Connection`) use it,
/// so the two can never disagree about what a valid time is.
enum UmbraDates {
  /// The time in `text`, or nil if it isn't an ISO 8601 time in either form.
  static func parse(_ text: String) -> Date? {
    if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) {
      return date
    }
    return try? Date.ISO8601FormatStyle().parse(text)
  }

  /// A time written for Umbra: with milliseconds, which Go reads fine.
  static func format(_ date: Date) -> String {
    date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
  }
}

/// The generated client's time reader and writer, built on `UmbraDates`.
struct UmbraDateTranscoder: DateTranscoder {
  struct NotATime: Error, CustomStringConvertible {
    let text: String
    var description: String { "Not an ISO 8601 time: \(text)" }
  }

  func encode(_ date: Date) throws -> String { UmbraDates.format(date) }

  func decode(_ text: String) throws -> Date {
    guard let date = UmbraDates.parse(text) else { throw NotATime(text: text) }
    return date
  }
}
