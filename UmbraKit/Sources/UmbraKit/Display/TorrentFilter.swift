import Foundation

/// The sidebar's status groups (web page: `statusFilters`).
public enum StatusFilter: String, Sendable, Hashable, CaseIterable {
  case all, downloading, seeding, paused, queued, errors

  /// The words in the sidebar.
  public var label: String {
    switch self {
    case .all: "All"
    case .downloading: "Downloading"
    case .seeding: "Seeding"
    case .paused: "Paused"
    case .queued: "Queued"
    case .errors: "Errors"
    }
  }

  /// Which group a torrent counts under (web page: `statusOf`). Waiting for
  /// disk space is queued; missing files count under Errors, where someone
  /// would look for them. Checking, moving and waiting for the VPN count as
  /// downloading while unfinished and as seeding once finished.
  public static func of(_ kind: StatusKind, progress: Double) -> StatusFilter {
    switch kind {
    case .error, .missingFiles: .errors
    case .paused: .paused
    case .queued, .waitingForSpace: .queued
    case .seeding: .seeding
    case .downloading, .fetchingDetails: .downloading
    case .checking, .moving, .waitingForVpn: progress >= 1 ? .seeding : .downloading
    }
  }
}

/// What the list shows: one status group, or one category, tag or tracker
/// (web page: `Filter`). An empty category or tracker means "none".
public enum TorrentFilter: Sendable, Hashable {
  case status(StatusFilter)
  case category(String)
  case tag(String)
  case tracker(String)

  /// Everything.
  public static let all = TorrentFilter.status(.all)

  /// Reads the filter's text form ("seeding", "category:films"); anything
  /// unknown is "all" (web page: `parseFilter`).
  public init(key: String) {
    let parts = key.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    let kind = String(parts[0])
    let value = parts.count > 1 ? String(parts[1]) : ""
    switch kind {
    case "category": self = .category(value)
    case "tag": self = .tag(value)
    case "tracker": self = .tracker(value)
    default: self = .status(StatusFilter(rawValue: kind) ?? .all)
    }
  }

  /// The text form, for remembering it (web page: `filterKey`).
  public var key: String {
    switch self {
    case .status(let status): status.rawValue
    case .category(let value): "category:\(value)"
    case .tag(let value): "tag:\(value)"
    case .tracker(let value): "tracker:\(value)"
    }
  }

  /// Whether `row` is shown with this filter and the search text `query`
  /// (web page: `matches`). The search looks for the text anywhere in the
  /// name, ignoring capitals.
  public func matches(_ row: TorrentRow, query: String = "") -> Bool {
    if !query.isEmpty,
      row.name.lowercased().range(of: query.lowercased(), options: .literal) == nil
    {
      return false
    }
    switch self {
    case .status(let status): return status == .all || row.group == status
    case .category(let value): return row.category == value
    case .tag(let value): return row.tags.contains(value)
    case .tracker(let value): return row.tracker == value
    }
  }

  /// What the sidebar counts for these rows.
  public static func counts(for rows: [TorrentRow]) -> TorrentCounts {
    TorrentCounts(rows)
  }
}

/// The sidebar's numbers: each status group, category, tag and tracker
/// (web page: `countAll`). Torrents with no category or tracker aren't
/// counted under one.
public struct TorrentCounts: Sendable, Equatable {
  public var status: [StatusFilter: Int]
  public var categories: [String: Int] = [:]
  public var tags: [String: Int] = [:]
  public var trackers: [String: Int] = [:]

  public init(_ rows: [TorrentRow]) {
    status = Dictionary(uniqueKeysWithValues: StatusFilter.allCases.map { ($0, 0) })
    status[.all] = rows.count
    for row in rows {
      status[row.group, default: 0] += 1
      if !row.category.isEmpty { categories[row.category, default: 0] += 1 }
      for tag in row.tags { tags[tag, default: 0] += 1 }
      if !row.tracker.isEmpty { trackers[row.tracker, default: 0] += 1 }
    }
  }

  /// The names in one of the groups, in alphabetical order for the sidebar.
  public static func sortedKeys(_ counts: [String: Int]) -> [String] {
    counts.keys.sorted { $0.localizedCompare($1) == .orderedAscending }
  }
}
