import Foundation
import UmbraAPI

/// One tracker, ready to show: the words and colour for how it is doing.
/// Follows the web page's Trackers tab.
public struct TrackerRow: Identifiable, Equatable, Sendable {
  public enum State: Sendable, Equatable {
    case working, notContacted, error
  }

  /// The address: unique within a torrent.
  public var id: String { url }
  public let url: String
  /// Lower tiers are asked first. As shown: the first tier is "Tier 1".
  public let tier: Int
  public let tierText: String
  public let state: State
  /// "Working", "Not contacted yet" or "Error".
  public let statusText: String
  public let symbolName: String
  public let role: ColorRole
  /// The tracker's own words when it failed ("Unregistered torrent").
  public let message: String?
  /// "12 seeds · 30 peers" as this tracker last counted them; nil if it hasn't.
  public let swarmText: String?
  /// "Next ask in 3m"; nil when not known.
  public let nextText: String?

  public init(_ t: Components.Schemas.Tracker, now: Date) {
    url = t.url
    tier = t.tier
    tierText = "Tier \(t.tier + 1)"
    switch t.state {
    case .working:
      state = .working
      statusText = "Working"
      symbolName = "checkmark.circle"
      role = .green
    case .notContacted:
      state = .notContacted
      statusText = "Not contacted yet"
      symbolName = "clock"
      role = .secondary
    case .error:
      state = .error
      statusText = "Error"
      symbolName = "exclamationmark.circle"
      role = .red
    }
    message = (t.message ?? "").isEmpty ? nil : t.message
    if t.seeds == nil && t.peers == nil {
      swarmText = nil
    } else {
      swarmText = "\(Self.count(t.seeds ?? 0, "seed")) · \(Self.count(t.peers ?? 0, "peer"))"
    }
    if let next = t.nextAnnounce {
      let seconds = next.timeIntervalSince(now)
      nextText = seconds <= 0 ? "Next ask now" : "Next ask in \(Format.eta(Int64(seconds)))"
    } else {
      nextText = nil
    }
  }

  /// "1 seed", "3 seeds".
  static func count(_ n: Int, _ word: String) -> String {
    "\(Format.count(n)) \(n == 1 ? word : word + "s")"
  }
}

/// One connected peer, ready to show.
public struct PeerRow: Identifiable, Equatable, Sendable {
  /// The address and port: unique within a torrent.
  public var id: String { address }
  public let address: String
  /// "Unknown client" when the peer doesn't say.
  public let client: String
  public let isEncrypted: Bool
  /// "Encrypted" or "Plain".
  public let encryptionText: String
  public let encryptionSymbol: String
  public let encryptionRole: ColorRole
  public let isIncoming: Bool
  /// "Incoming" (the peer connected to Umbra) or "Outgoing".
  public let directionText: String
  /// How much of the torrent the peer has, 0 to 1.
  public let progress: Double
  public let progressText: String
  public let downSpeed: Int64
  public let downText: String
  public let upSpeed: Int64
  public let upText: String

  public init(_ p: Components.Schemas.Peer) {
    address = p.address
    client = (p.client ?? "").isEmpty ? "Unknown client" : p.client ?? ""
    isEncrypted = p.encrypted
    encryptionText = p.encrypted ? "Encrypted" : "Plain"
    encryptionSymbol = p.encrypted ? "lock" : "lock.open"
    encryptionRole = p.encrypted ? .green : .orange
    isIncoming = p.incoming
    directionText = p.incoming ? "Incoming" : "Outgoing"
    progress = p.progress
    progressText = Format.percent(p.progress)
    downSpeed = p.downSpeed
    downText = Format.speed(p.downSpeed, zero: "0 B/s")
    upSpeed = p.upSpeed
    upText = Format.speed(p.upSpeed, zero: "0 B/s")
  }

  /// The peers busiest first (as the web page lists them), ties by address
  /// so the order doesn't shuffle between fetches.
  public static func rows(_ peers: [Components.Schemas.Peer]) -> [PeerRow] {
    peers.sorted { a, b in
      let aBusy = a.downSpeed + a.upSpeed
      let bBusy = b.downSpeed + b.upSpeed
      return aBusy != bBusy ? aBusy > bBusy : a.address < b.address
    }.map(PeerRow.init)
  }

  /// What to say when there are no peers (web page wording).
  public static func emptyText(for kind: StatusKind?) -> String {
    switch kind {
    case .paused, .queued, .waitingForSpace:
      "Not connected to any peers while it isn't running."
    default:
      "No peers connected yet."
    }
  }
}

/// The inspector's short summary when several torrents are selected.
public struct SelectionSummary: Equatable, Sendable {
  public let count: Int
  /// "3 torrents selected"
  public let title: String
  /// "5.2 GB total · ↓ 3.1 MB/s · ↑ 0 B/s"
  public let detail: String

  public init(_ rows: [TorrentRow]) {
    count = rows.count
    title = "\(Format.count(rows.count)) torrents selected"
    let size = rows.reduce(Int64(0)) { $0 + $1.size }
    let down = rows.reduce(Int64(0)) { $0 + $1.downSpeed }
    let up = rows.reduce(Int64(0)) { $0 + $1.upSpeed }
    detail =
      "\(Format.bytes(size)) total · ↓ \(Format.speed(down, zero: "0 B/s")) · ↑ \(Format.speed(up, zero: "0 B/s"))"
  }
}
