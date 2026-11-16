import Foundation
import UmbraAPI

/// The three kinds of notification, each with its own switch.
public enum NotificationKind: String, CaseIterable, Sendable, Equatable {
  case finished, problem, vpn
}

/// Which kinds the person wants. All on to begin with.
public struct NotificationSwitches: Equatable, Sendable {
  public var finished: Bool
  public var problem: Bool
  public var vpn: Bool

  public init(finished: Bool = true, problem: Bool = true, vpn: Bool = true) {
    self.finished = finished
    self.problem = problem
    self.vpn = vpn
  }

  public func isOn(_ kind: NotificationKind) -> Bool {
    switch kind {
    case .finished: finished
    case .problem: problem
    case .vpn: vpn
    }
  }
}

/// One notification to show: the words, and which torrent a click selects.
public struct PlannedNotification: Equatable, Sendable {
  public let kind: NotificationKind
  public let title: String
  public let body: String
  /// The torrent a click selects; nil for the VPN and for summaries (a
  /// click then only brings the window forward).
  public let torrentHash: String?

  public init(kind: NotificationKind, title: String, body: String, torrentHash: String? = nil) {
    self.kind = kind
    self.title = title
    self.body = body
    self.torrentHash = torrentHash
  }
}

/// What the app knew at one moment, for `NotificationPlanner`.
public struct NotificationSnapshot: Sendable {
  public let torrents: [Components.Schemas.Torrent]
  public let transfer: Components.Schemas.Transfer?
  /// Umbra is connected and this connection's list has arrived. While it
  /// is false nothing is planned, and the planner forgets what it knew.
  public let connected: Bool
  public let now: Date

  public init(
    torrents: [Components.Schemas.Torrent], transfer: Components.Schemas.Transfer?,
    connected: Bool, now: Date
  ) {
    self.torrents = torrents
    self.transfer = transfer
    self.connected = connected
    self.now = now
  }
}

/// Decides which notifications to send. It is fed one snapshot after
/// another and says what to show. It never talks to macOS.
///
/// The rules:
/// - The first snapshot after connecting only sets the starting point.
///   Nothing is said about what was already true then.
/// - Losing the connection makes it forget everything, so connecting again
///   (after the helper restarts) starts afresh and replays nothing.
/// - A download is "finished" only if it was seen downloading since the
///   app connected, and is now complete. Each torrent is announced once.
/// - A problem is announced once for each torrent and problem.
/// - The VPN is announced when it goes down or is held, and when it comes
///   back after that. At most one VPN notification every 30 seconds, and
///   it says how things are now.
/// - More than 3 finishes in 10 seconds become one summary.
/// - A switch that is off silences its kind. The planner still follows
///   events, so turning a switch on later never replays old news.
public struct NotificationPlanner: Sendable {
  /// A summary replaces individual notices past this many in the window.
  static let summaryLimit = 3
  static let summaryWindow: TimeInterval = 10
  static let vpnSpacing: TimeInterval = 30

  /// What the person was last told about the VPN.
  enum VpnNews: Equatable, Sendable {
    case down
    case held(Components.Schemas.VpnHeldReason?)
    case up
  }

  private var primed = false
  /// Torrents seen downloading, and not yet announced as finished.
  private var seenDownloading: Set<String> = []
  /// Torrents already announced as finished.
  private var announcedFinished: Set<String> = []
  /// Each torrent's current problem, once it has been seen (or announced).
  private var problems: [String: String] = [:]
  /// When recent finishes were announced, for the summary rule.
  private var recentFinishes: [Date] = []
  private var vpnPrimed = false
  private var vpnNews: VpnNews?
  /// The person was told the VPN is down or held (so "back" is news).
  private var vpnTold = false
  private var lastVpnSent: Date?

  public init() {}

  /// Takes the next snapshot and returns what to show, in order.
  public mutating func plan(
    _ snapshot: NotificationSnapshot, switches: NotificationSwitches
  ) -> [PlannedNotification] {
    guard snapshot.connected else {
      self = NotificationPlanner()
      return []
    }
    var result: [PlannedNotification] = []
    let first = !primed
    primed = true
    result += torrentNews(snapshot, first: first, switches: switches)
    result += vpnNews(snapshot, switches: switches)
    return result
  }

  // MARK: Torrents

  private mutating func torrentNews(
    _ snapshot: NotificationSnapshot, first: Bool, switches: NotificationSwitches
  ) -> [PlannedNotification] {
    var finished: [Components.Schemas.Torrent] = []
    var problemNotes: [PlannedNotification] = []
    let listed = Set(snapshot.torrents.map(\.hash))
    // Torrents that left the list are forgotten.
    seenDownloading.formIntersection(listed)
    announcedFinished.formIntersection(listed)
    problems = problems.filter { listed.contains($0.key) }

    for torrent in snapshot.torrents {
      let hash = torrent.hash
      // Finished.
      if torrent.state == .downloading && torrent.progress < 1 {
        seenDownloading.insert(hash)
      }
      if torrent.progress >= 1, !announcedFinished.contains(hash) {
        // One that was not seen downloading (complete at connect, or added
        // complete) is never announced, nor after a later recheck.
        if seenDownloading.contains(hash) && !first { finished.append(torrent) }
        announcedFinished.insert(hash)
        seenDownloading.remove(hash)
      }
      // Problems.
      if let key = Self.problemKey(torrent) {
        if problems[hash] != key {
          problems[hash] = key
          if !first { problemNotes.append(Self.problemNotice(torrent)) }
        }
      } else {
        problems[hash] = nil
      }
    }

    var result: [PlannedNotification] = []
    if switches.finished {
      result += finishNotices(finished, now: snapshot.now)
    }
    if switches.problem { result += problemNotes }
    return result
  }

  private mutating func finishNotices(
    _ finished: [Components.Schemas.Torrent], now: Date
  ) -> [PlannedNotification] {
    recentFinishes = recentFinishes.filter { now.timeIntervalSince($0) < Self.summaryWindow }
    guard !finished.isEmpty else { return [] }
    let total = recentFinishes.count + finished.count
    recentFinishes += Array(repeating: now, count: finished.count)
    if total > Self.summaryLimit {
      return [
        PlannedNotification(
          kind: .finished, title: "\(total) downloads finished",
          body: "Open Umbra to see them.")
      ]
    }
    return finished.map {
      PlannedNotification(
        kind: .finished, title: $0.name, body: "Download finished", torrentHash: $0.hash)
    }
  }

  /// A word for the torrent's problem, nil when it has none. The same
  /// states the list's Status column shows as trouble.
  static func problemKey(_ torrent: Components.Schemas.Torrent) -> String? {
    switch StatusKind(torrent.state) {
    case .error, .missingFiles:
      return "\(torrent.state.rawValue): \(torrent.error ?? "")"
    default:
      return nil
    }
  }

  private static func problemNotice(_ torrent: Components.Schemas.Torrent) -> PlannedNotification {
    let kind = StatusKind(torrent.state)
    let said = (torrent.error ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let body = said.isEmpty ? (kind == .error ? "Something went wrong." : kind.label) : said
    return PlannedNotification(
      kind: .problem, title: torrent.name, body: body, torrentHash: torrent.hash)
  }

  // MARK: The VPN

  private mutating func vpnNews(
    _ snapshot: NotificationSnapshot, switches: NotificationSwitches
  ) -> [PlannedNotification] {
    // The totals arrive a moment after the list; the first ones set the starting point.
    guard let transfer = snapshot.transfer else { return [] }
    let current: VpnNews?
    switch transfer.vpn {
    case .down: current = .down
    case .held: current = .held(transfer.vpnHeldReason)
    case .connected, .connecting, .none: current = nil
    }
    guard vpnPrimed else {
      // The first state seen is the starting point: said nothing about.
      vpnPrimed = true
      vpnNews = current
      vpnTold = false
      return []
    }
    var wanted = current
    if transfer.vpn == .connected, vpnTold, vpnNews != .up { wanted = .up }
    guard let wanted else {
      // Fine again, or not a state worth a notice (connecting, no VPN).
      if transfer.vpn == .connected || transfer.vpn == .none { vpnNews = nil }
      return []
    }
    guard wanted != vpnNews else { return [] }
    if let last = lastVpnSent, snapshot.now.timeIntervalSince(last) < Self.vpnSpacing {
      // Too soon: wait. The next snapshot reports the state as it is then.
      return []
    }
    vpnNews = wanted
    vpnTold = wanted != .up
    lastVpnSent = snapshot.now
    guard switches.vpn else { return [] }
    return [Self.vpnNotice(transfer, wanted)]
  }

  private static func vpnNotice(
    _ transfer: Components.Schemas.Transfer, _ news: VpnNews
  ) -> PlannedNotification {
    // The words are the ones the toolbar pill and its popover use.
    let summary = VpnSummary(transfer: transfer, status: nil, connection: .live)
    switch news {
    case .down, .held:
      return PlannedNotification(
        kind: .vpn, title: summary.pill.title, body: summary.details.sentence)
    case .up:
      return PlannedNotification(
        kind: .vpn, title: "VPN connected again", body: summary.details.sentence)
    }
  }
}
