import UmbraAPI

/// Which of the system's colours something is drawn in. Only roles, never
/// colour values: the app uses the system's own colours (and the person's
/// accent colour), so it looks right in light and dark.
public enum ColorRole: Sendable, Equatable {
  case accent, green, orange, red, secondary
}

/// What a torrent is doing, as the Status column shows it: one per state
/// Umbra reports, with the web page's words (`web/src/lib/torrents.ts`,
/// `states`), an SF Symbol in place of the web page's icon, and colour
/// roles in place of its colours.
public enum StatusKind: String, Sendable, Equatable, CaseIterable {
  case downloading, seeding, paused, queued, checking, moving, fetchingDetails, error
  /// Would run, but the VPN kill switch holds it.
  case waitingForVpn
  /// A download that would take its disk below the space kept free.
  case waitingForSpace
  /// A finished torrent whose files were moved or deleted outside Umbra.
  case missingFiles

  public init(_ state: Components.Schemas.TorrentState) {
    switch state {
    case .downloading: self = .downloading
    case .seeding: self = .seeding
    case .paused: self = .paused
    case .queued: self = .queued
    case .checking: self = .checking
    case .moving: self = .moving
    case .fetchingDetails: self = .fetchingDetails
    case .error: self = .error
    case .waitingForVpn: self = .waitingForVpn
    case .waitingForSpace: self = .waitingForSpace
    case .missingFiles: self = .missingFiles
    }
  }

  /// The words in the Status column. The Mac app's own words where they
  /// read better in a Mac list ("Verifying", "Getting metadata"); otherwise
  /// the web page's.
  public var label: String {
    switch self {
    case .downloading: "Downloading"
    case .seeding: "Seeding"
    case .paused: "Paused"
    case .queued: "Queued"
    case .checking: "Verifying"
    case .moving: "Moving"
    case .fetchingDetails: "Getting metadata"
    case .error: "Error"
    case .waitingForVpn: "Waiting for VPN"
    case .waitingForSpace: "Waiting for disk space"
    case .missingFiles: "Files missing"
    }
  }

  /// The SF Symbol beside the words (the nearest match to the web page's icon).
  public var symbolName: String {
    switch self {
    case .downloading: "arrow.down"
    case .seeding: "arrow.up"
    case .paused: "pause"
    case .queued: "clock"
    case .checking: "arrow.clockwise"
    case .moving: "shippingbox"
    case .fetchingDetails: "magnifyingglass"
    case .error: "exclamationmark.circle"
    case .waitingForVpn: "lock.shield"
    case .waitingForSpace: "internaldrive"
    case .missingFiles: "questionmark.folder"
    }
  }

  /// The colour of the status words (the web page's text colour).
  public var textRole: ColorRole {
    switch self {
    case .downloading, .fetchingDetails: .accent
    case .seeding: .green
    case .paused, .queued: .secondary
    case .checking, .moving, .waitingForVpn, .waitingForSpace, .missingFiles: .orange
    case .error: .red
    }
  }

  /// The colour of the progress bar (the web page's bar tone).
  public var barRole: ColorRole {
    switch self {
    case .downloading, .fetchingDetails: .accent
    case .seeding: .green
    case .paused, .queued, .waitingForVpn, .waitingForSpace, .missingFiles: .secondary
    case .checking, .moving: .orange
    case .error: .red
    }
  }

  /// Stopped by something it waits for: its speeds show as a dash, not a figure.
  var isWaiting: Bool { self == .waitingForVpn || self == .waitingForSpace }
}
