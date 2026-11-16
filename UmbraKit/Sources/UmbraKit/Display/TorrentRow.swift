import Foundation
import UmbraAPI

/// One line of the torrent list, ready to show: the raw values (for sorting
/// and filtering) and the words each column shows, worked out once when the
/// row is made, following the web page's `columns.tsx` cell by cell.
public struct TorrentRow: Identifiable, Equatable, Sendable {
  /// A line under the name: what went wrong (red), where the files went
  /// (orange), or why it waits for disk space (orange).
  public struct Note: Equatable, Sendable {
    public let text: String
    public let role: ColorRole
  }

  /// The info hash: a torrent's id.
  public let id: String
  public var hash: String { id }
  public let name: String
  public let kind: StatusKind
  /// Which sidebar status group it counts under.
  public let group: StatusFilter
  public let note: Note?
  /// Umbra's own words for an error, missing files or a seed goal reached.
  public let error: String?

  public let size: Int64
  public let sizeText: String
  public let progress: Double
  public let progressText: String
  /// How full the progress bar is: empty while a magnet fetches its details.
  public let barValue: Double
  public let downSpeed: Int64
  public let downSpeedText: String
  public let upSpeed: Int64
  public let upSpeedText: String
  public let etaSeconds: Int64?
  public let etaText: String
  public let ratio: Double
  public let ratioText: String
  /// Empty when none.
  public let category: String
  public let categoryText: String
  public let tags: [String]
  public let addedAt: Date
  public let addedText: String
  public let completedAt: Date?
  public let completedText: String
  public let seeds: Int
  public let seedsTotal: Int
  /// "7 (12)": connected, and the swarm's total when it means something.
  public let seedsText: String
  public let peers: Int
  public let peersTotal: Int
  public let peersText: String
  public let downloaded: Int64
  public let downloadedText: String
  public let uploaded: Int64
  public let uploadedText: String
  public let seedTimeSeconds: Int64
  public let seedTimeText: String
  /// The tracker's host; empty for a trackerless torrent.
  public let tracker: String
  public let trackerText: String
  public let savePath: String
  /// 1 is next to run; 0 when not queued.
  public let queuePosition: Int
  public let queueText: String
  /// Umbra made this torrent from the person's own files and seeds it from
  /// where they are (Create Torrent, seeding on): deleting its files
  /// deletes their originals, not a download.
  public let madeFromOwnFiles: Bool

  /// The status words.
  public var statusLabel: String { kind.label }
  /// How many peers it is connected to, seeds included (the Peers tab's number).
  public var connected: Int { seeds + peers }

  /// Makes the row. `now` decides "Today" and "Yesterday".
  public init(
    _ t: Components.Schemas.Torrent, now: Date, style: Format.DateStyle = .current
  ) {
    let kind = StatusKind(t.state)
    id = t.hash
    name = t.name
    self.kind = kind
    group = StatusFilter.of(kind, progress: t.progress)
    note = Self.note(t)
    error = t.error

    size = t.size
    sizeText = t.size > 0 ? Format.bytes(t.size) : Format.dash
    progress = t.progress
    progressText = kind == .fetchingDetails ? Format.dash : Format.percent(t.progress)
    barValue = kind == .fetchingDetails ? 0 : t.progress
    downSpeed = t.downSpeed
    upSpeed = t.upSpeed
    // A torrent stopped by what it waits for shows a dash, not a speed.
    downSpeedText = kind.isWaiting ? Format.dash : Format.speed(t.downSpeed)
    upSpeedText = kind.isWaiting ? Format.dash : Format.speed(t.upSpeed)
    etaSeconds = t.etaSeconds
    etaText = Format.eta(t.etaSeconds)
    ratio = t.ratio
    ratioText = Format.ratio(t.ratio)
    category = t.category
    categoryText = t.category.isEmpty ? Format.dash : t.category
    tags = t.tags
    addedAt = t.addedAt
    addedText = Format.shortDate(t.addedAt, now: now, style: style)
    completedAt = t.completedAt
    completedText = Format.shortDate(t.completedAt, now: now, style: style)
    seeds = t.seeds
    seedsTotal = t.seedsTotal
    seedsText = Self.withTotal(t.seeds, t.seedsTotal)
    peers = t.peers
    peersTotal = t.peersTotal
    peersText = Self.withTotal(t.peers, t.peersTotal)
    downloaded = t.downloaded
    downloadedText = Format.bytes(t.downloaded)
    uploaded = t.uploaded
    uploadedText = Format.bytes(t.uploaded)
    seedTimeSeconds = t.seedTimeSeconds
    seedTimeText = Format.duration(t.seedTimeSeconds)
    tracker = t.tracker ?? ""
    trackerText = (t.tracker ?? "").isEmpty ? Format.dash : t.tracker ?? ""
    savePath = t.savePath
    queuePosition = t.queuePosition
    queueText = t.queuePosition != 0 ? String(t.queuePosition) : Format.dash
    madeFromOwnFiles = t.madeFromOwnFiles ?? false
  }

  /// The swarm's total to show beside the connected count, or none (web
  /// page: `swarmTotal`). The total is only what the trackers last said,
  /// so it can be lower than what Umbra is connected to; "7 of 0" read as a
  /// bug, so then only the connected count shows.
  public static func swarmTotal(connected: Int, total: Int) -> Int? {
    total >= connected ? total : nil
  }

  static func withTotal(_ connected: Int, _ total: Int) -> String {
    swarmTotal(connected: connected, total: total).map { "\(connected) (\($0))" } ?? "\(connected)"
  }

  /// Why a download waits for disk space, in a line (web page: `spaceLine`):
  /// "Needs 12.3 GB; 8.0 GB free, 5.0 GB kept free", adding "and 4.0 GB for
  /// other downloads" when the room is theirs.
  public static func spaceLine(_ t: Components.Schemas.Torrent) -> String? {
    guard t.state == .waitingForSpace, let wait = t.spaceWait else { return nil }
    let line =
      "Needs \(Format.bytes(wait.need)); \(Format.bytes(wait.free)) free, \(Format.bytes(wait.keep)) kept free"
    return wait.others > 0 ? "\(line) and \(Format.bytes(wait.others)) for other downloads" : line
  }

  /// The line under the name (web page: `noteOf`).
  public static func note(_ t: Components.Schemas.Torrent) -> Note? {
    if t.state == .error, let error = t.error, !error.isEmpty {
      return Note(text: error, role: .red)
    }
    if t.state == .missingFiles, let error = t.error, !error.isEmpty {
      return Note(text: error, role: .orange)
    }
    return spaceLine(t).map { Note(text: $0, role: .orange) }
  }
}
