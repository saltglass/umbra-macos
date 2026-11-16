import Foundation
import UmbraAPI

/// Everything the menu bar item and its panel show, worked out in one
/// place so every rule is tested. The views only draw what is here.
///
/// It takes what the rest of the app already knows: the torrents, the
/// totals, where the session is, and the VPN's words (`VpnSummary`, so the
/// panel says exactly what the toolbar's VPN pill says). It decides
/// nothing about the VPN itself.
public struct MenuBarSummary: Equatable, Sendable {
  /// Which picture the menu bar shows. Always a symbol, never a colour trick.
  public enum Icon: Equatable, Sendable {
    /// Umbra is running and nothing needs attention.
    case normal
    /// The VPN is down or removed, or torrents are held for it.
    case attention
    /// Umbra isn't running or isn't answering.
    case notConnected

    /// The SF Symbol.
    public var symbol: String {
      switch self {
      case .normal: "arrow.up.arrow.down.circle"
      case .attention: "exclamationmark.shield"
      case .notConnected: "bolt.slash.circle"
      }
    }

    /// What VoiceOver says for the item.
    public var help: String {
      switch self {
      case .normal: "Umbra"
      case .attention: "Umbra: the VPN needs attention"
      case .notConnected: "Umbra: not running"
      }
    }
  }

  /// The VPN block: the same symbol, colour and words as the pill's popover.
  public struct Vpn: Equatable, Sendable {
    public let symbol: String
    public let role: ColorRole
    public let title: String
    public let sentence: String
    /// The address peers see, when it is known.
    public let address: String?
    /// Whether to offer "Open VPN Settings…".
    public let offersSettings: Bool
  }

  /// One line of the "Active" list.
  public struct ActiveTorrent: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    /// "41m", or a dash when Umbra can't tell.
    public let eta: String
    /// 0 to 1.
    public let progress: Double
  }

  /// How many downloads the "Active" list shows.
  public static let activeLimit = 5

  /// "Umbra".
  public let heading = "Umbra"
  /// "5 downloading · 6 seeding", "Nothing active", "Starting…"...
  public let countsLine: String
  public let icon: Icon
  /// Whether Umbra is running and its live list can be trusted.
  public let isConnected: Bool
  /// Nil when Umbra isn't running (nothing to say about the VPN then).
  public let vpn: Vpn?
  /// Whether the two speed tiles show. They show a dash while the live
  /// list is not open.
  public let showsSpeeds: Bool
  /// "8.4 MB/s", "0 B/s", or a dash.
  public let downSpeed: String
  public let upSpeed: String
  /// The fastest downloads, at most `activeLimit` of them.
  public let active: [ActiveTorrent]
  /// How many more downloads there are than `active` shows.
  public let moreActive: Int
  /// "and 3 more", when there are more.
  public var moreLine: String? { moreActive > 0 ? "and \(Format.count(moreActive)) more" : nil }

  public let slowMode: Bool
  public let slowModeEnabled: Bool
  /// Pause All is offered when something can be paused.
  public let canPauseAll: Bool
  public let canResumeAll: Bool
  /// What Pause All sends: every torrent that isn't paused already.
  public let pauseAllHashes: [String]
  /// What Resume All sends: every torrent that is paused or stopped by an
  /// error or missing files (Umbra's resume tries those again).
  public let resumeAllHashes: [String]

  /// - Parameters:
  ///   - slowMode: slow mode as the window shows it (it may be ahead of the totals).
  ///   - feed: whether the live feed is open.
  public init(
    torrents: [Components.Schemas.Torrent], transfer: Components.Schemas.Transfer?,
    phase: AppSession.Phase, feed: FeedConnectionState, vpn summary: VpnSummary,
    slowMode: Bool
  ) {
    let running = phase == .running
    let connected = running && feed == .live
    isConnected = connected

    // One pass over the torrents.
    var downloading: [Components.Schemas.Torrent] = []
    var seeding = 0
    var heldForVpn = false
    var pausable: [String] = []
    var resumable: [String] = []
    for torrent in torrents {
      let kind = StatusKind(torrent.state)
      switch kind {
      case .downloading: downloading.append(torrent)
      case .seeding: seeding += 1
      case .waitingForVpn: heldForVpn = true
      default: break
      }
      if TorrentSelection.canPause(kind) { pausable.append(torrent.hash) }
      if TorrentSelection.canResume(kind) { resumable.append(torrent.hash) }
    }

    countsLine = Self.countsLine(
      downloading: downloading.count, seeding: seeding, phase: phase, feed: feed)

    let vpnKind = summary.pill.kind
    if !connected {
      icon = .notConnected
    } else if vpnKind == .held || vpnKind == .down || heldForVpn {
      icon = .attention
    } else {
      icon = .normal
    }

    if running {
      let details = summary.details
      // The address is a fact drawn in monospace; "Checking…" and
      // "Couldn't check" are not addresses.
      let address = details.facts.first { $0.label == "Address peers see" && $0.monospaced }?.value
      vpn = Vpn(
        symbol: details.symbol, role: details.role, title: details.title,
        sentence: details.sentence, address: address, offersSettings: details.offersVpnSettings)
    } else {
      vpn = nil
    }

    showsSpeeds = running
    downSpeed = connected ? Format.speed(transfer?.downSpeed, zero: "0 B/s") : Format.dash
    upSpeed = connected ? Format.speed(transfer?.upSpeed, zero: "0 B/s") : Format.dash

    // Fastest first; the name and then the hash settle ties, so the list
    // doesn't shuffle from one second to the next.
    let fastest = downloading.sorted {
      if $0.downSpeed != $1.downSpeed { return $0.downSpeed > $1.downSpeed }
      if $0.name != $1.name { return $0.name < $1.name }
      return $0.hash < $1.hash
    }
    active = fastest.prefix(Self.activeLimit).map {
      ActiveTorrent(
        id: $0.hash, name: $0.name, eta: Format.eta($0.etaSeconds), progress: $0.progress)
    }
    moreActive = max(0, fastest.count - Self.activeLimit)

    self.slowMode = slowMode
    slowModeEnabled = connected
    pauseAllHashes = connected ? pausable : []
    resumeAllHashes = connected ? resumable : []
    canPauseAll = !pauseAllHashes.isEmpty
    canResumeAll = !resumeAllHashes.isEmpty
  }

  static func countsLine(
    downloading: Int, seeding: Int, phase: AppSession.Phase, feed: FeedConnectionState
  ) -> String {
    switch phase {
    case .starting: return "Starting…"
    case .reconnecting: return "Reconnecting…"
    case .saving: return "Saving…"
    case .stopped, .failed: return "Not running"
    case .running:
      switch feed {
      case .live: break
      case .connecting: return "Connecting…"
      case .reconnecting: return "Reconnecting…"
      case .refused: return "Not connected"
      }
    }
    var parts: [String] = []
    if downloading > 0 { parts.append("\(Format.count(downloading)) downloading") }
    if seeding > 0 { parts.append("\(Format.count(seeding)) seeding") }
    return parts.isEmpty ? "Nothing active" : parts.joined(separator: " · ")
  }
}
