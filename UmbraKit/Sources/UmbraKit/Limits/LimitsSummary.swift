import Foundation
import UmbraAPI

/// A torrent's own limits as rows for the inspector's General tab. Only
/// the limits it has of its own are listed: a torrent with none shows a
/// single line saying so.
public struct LimitsSummary: Equatable, Sendable {
  public struct Row: Equatable, Sendable, Identifiable {
    public var id: String { title }
    public let title: String
    public let value: String
  }

  public let rows: [Row]

  /// Shown when the torrent has no limits of its own.
  public static let noneText = "None of its own"

  public var isEmpty: Bool { rows.isEmpty }

  public init(_ own: Components.Schemas.OwnLimits, locale: Locale = .current) {
    let f = LimitFormats(locale: locale)
    var rows: [Row] = []
    func add(_ field: LimitField, _ value: String?) {
      if let value { rows.append(Row(title: field.summaryTitle, value: value)) }
    }
    func speed(_ kbs: Int) -> String? { kbs > 0 ? "\(f.speed.text(kbs)) MB/s" : nil }
    add(.downloadLimit, speed(own.downloadLimitKBs))
    add(.uploadLimit, speed(own.uploadLimitKBs))
    add(.ratio, own.ratio.map { $0 < 0 ? "None" : f.ratio.text($0) })
    add(
      .seedingTime, own.seedingMinutes.map { $0 < 0 ? "None" : f.seedingTime.text($0) + " hours" })
    add(
      .inactiveTime, own.inactiveMinutes.map { $0 < 0 ? "None" : f.inactiveTime.text($0) + " min" })
    self.rows = rows
  }
}
