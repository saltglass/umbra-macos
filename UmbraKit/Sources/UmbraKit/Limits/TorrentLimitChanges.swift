import Foundation

/// What to do with one of a torrent's own limits.
public enum LimitChange<Value: Equatable & Sendable>: Equatable, Sendable {
  /// Leave it as each torrent has it (the field is not sent).
  case keep
  /// Take the torrent's own limit away, so its category's (else the
  /// global) setting applies. For a seed goal Umbra reads this as `null`;
  /// for a speed, as 0.
  case useDefault
  /// A seed goal only: this torrent has no goal at all (Umbra reads a
  /// negative number as that).
  case noGoal
  case set(Value)
}

/// Changes to some torrents' own limits, as Umbra's "set limits" call
/// takes them: only the fields that are not `.keep` are sent.
public struct TorrentLimitChanges: Equatable, Sendable {
  public var ratio: LimitChange<Double> = .keep
  public var seedingMinutes: LimitChange<Int> = .keep
  public var inactiveMinutes: LimitChange<Int> = .keep
  /// Speeds are in KB/s, as Umbra keeps them.
  public var downloadLimitKBs: LimitChange<Int> = .keep
  public var uploadLimitKBs: LimitChange<Int> = .keep

  public init() {}

  /// True when nothing would be sent.
  public var isEmpty: Bool {
    ratio == .keep && seedingMinutes == .keep && inactiveMinutes == .keep
      && downloadLimitKBs == .keep && uploadLimitKBs == .keep
  }

  /// The exact JSON Umbra is sent. The generated request type can't say
  /// `null` (it drops empty fields), and `null` is how a seed goal goes
  /// back to following its category, so the body is written here.
  func body(hashes: [String]) -> Data {
    var json: [String: Any] = ["hashes": hashes]
    func goal<T>(_ key: String, _ change: LimitChange<T>, none: T) {
      switch change {
      case .keep: break
      case .useDefault: json[key] = NSNull()
      case .noGoal: json[key] = none
      case .set(let value): json[key] = value
      }
    }
    func speed(_ key: String, _ change: LimitChange<Int>) {
      switch change {
      case .keep: break
      case .useDefault, .noGoal: json[key] = 0
      case .set(let value): json[key] = value
      }
    }
    goal("ratio", ratio, none: -1.0)
    goal("seedingMinutes", seedingMinutes, none: -1)
    goal("inactiveMinutes", inactiveMinutes, none: -1)
    speed("downloadLimitKBs", downloadLimitKBs)
    speed("uploadLimitKBs", uploadLimitKBs)
    return (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data()
  }
}
