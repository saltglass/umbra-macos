import Foundation
import UmbraAPI

/// A list column. It is Umbra's own column list (`ColumnId` in the API), so
/// a sort or column choice reads the same here and on the web page.
public typealias TorrentColumn = Components.Schemas.ColumnId

/// How the list is sorted: one column, up or down (web page: `Sort` and
/// `sortTorrents`).
///
/// It is also a `SortComparator`, so a SwiftUI `Table` can sort with it
/// directly when a column header is clicked.
public struct TorrentSort: Sendable, Hashable, SortComparator {
  public var column: TorrentColumn
  public var descending: Bool

  public init(column: TorrentColumn, descending: Bool) {
    self.column = column
    self.descending = descending
  }

  /// A new list's sort: newest first.
  public static let `default` = TorrentSort(column: .addedAt, descending: true)

  /// The sort for a header click (web page: `onSort`): the same column
  /// turns round; another starts high to low for numbers and dates, A to Z
  /// for words.
  public func clicked(_ column: TorrentColumn) -> TorrentSort {
    if column == self.column { return TorrentSort(column: column, descending: !descending) }
    return TorrentSort(column: column, descending: column.sortsDescendingFirst)
  }

  /// The rows in this order. Ties go by name, then hash, so the order never
  /// jumps about between updates.
  public func sorted(_ rows: [TorrentRow]) -> [TorrentRow] {
    rows.sorted { compare($0, $1) == .orderedAscending }
  }

  // MARK: SortComparator

  public var order: SortOrder {
    get { descending ? .reverse : .forward }
    set { descending = newValue == .reverse }
  }

  public func compare(_ a: TorrentRow, _ b: TorrentRow) -> ComparisonResult {
    let byColumn = Self.key(column, a).compare(Self.key(column, b))
    if byColumn != .orderedSame {
      // Turning the order round turns only the column's order round, not
      // the tie-breaks, as on the web page.
      if !descending { return byColumn }
      return byColumn == .orderedAscending ? .orderedDescending : .orderedAscending
    }
    let byName = a.name.localizedCompare(b.name)
    if byName != .orderedSame { return byName }
    return a.hash.localizedCompare(b.hash)
  }

  // MARK: Sort values

  /// What a column sorts by: words or a number.
  enum Key {
    case text(String)
    case number(Double)

    func compare(_ other: Key) -> ComparisonResult {
      switch (self, other) {
      case (.number(let x), .number(let y)):
        return x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame
      case (.text(let x), .text(let y)):
        // JavaScript compares words by their UTF-16 code units; this does the same.
        if x.utf16.elementsEqual(y.utf16) { return .orderedSame }
        return x.utf16.lexicographicallyPrecedes(y.utf16) ? .orderedAscending : .orderedDescending
      default:
        return .orderedSame  // a column always gives one kind
      }
    }
  }

  /// The value a column sorts by (web page: `sortValue`).
  static func key(_ column: TorrentColumn, _ row: TorrentRow) -> Key {
    switch column {
    case .name: .text(row.name.lowercased())
    case .size: .number(Double(row.size))
    case .progress: .number(row.progress)
    case .status: .text(row.kind.label)
    case .downSpeed: .number(Double(row.downSpeed))
    case .upSpeed: .number(Double(row.upSpeed))
    // Unknown times left go last, going up.
    case .eta: .number(row.etaSeconds.map(Double.init) ?? .infinity)
    case .ratio: .number(row.ratio)
    case .category: .text(row.category.lowercased())
    case .tags: .text(row.tags.joined(separator: ",").lowercased())
    case .addedAt: .number(row.addedAt.timeIntervalSince1970)
    case .seeds: .number(Double(row.seeds))
    case .peers: .number(Double(row.peers))
    case .downloaded: .number(Double(row.downloaded))
    case .uploaded: .number(Double(row.uploaded))
    case .seedTime: .number(Double(row.seedTimeSeconds))
    case .tracker: .text(row.tracker.lowercased())
    case .savePath: .text(row.savePath.lowercased())
    // Never finished comes first, going up.
    case .completedAt: .number(row.completedAt?.timeIntervalSince1970 ?? -.infinity)
    // Not queued goes last, going up.
    case .queuePosition: .number(row.queuePosition != 0 ? Double(row.queuePosition) : .infinity)
    }
  }
}

extension Components.Schemas.ColumnId {
  /// The column's header (web page: `columns.tsx`).
  public var header: String {
    switch self {
    case .name: "Name"
    case .size: "Size"
    case .progress: "Progress"
    case .status: "Status"
    case .downSpeed: "Down"
    case .upSpeed: "Up"
    case .eta: "ETA"
    case .ratio: "Ratio"
    case .category: "Category"
    case .tags: "Tags"
    case .addedAt: "Added"
    case .seeds: "Seeds"
    case .peers: "Peers"
    case .downloaded: "Downloaded"
    case .uploaded: "Uploaded"
    case .seedTime: "Seed time"
    case .tracker: "Tracker"
    case .savePath: "Save path"
    case .completedAt: "Completed"
    case .queuePosition: "Queue"
    }
  }

  /// The column's name in a Columns menu, where it differs from the header.
  public var menuLabel: String {
    switch self {
    case .downSpeed: "Down speed"
    case .upSpeed: "Up speed"
    case .completedAt: "Completed on"
    case .queuePosition: "Queue position"
    default: header
    }
  }

  /// Figures line up on the right.
  public var alignsRight: Bool {
    switch self {
    case .size, .progress, .downSpeed, .upSpeed, .eta, .ratio, .seeds, .peers, .downloaded,
      .uploaded, .seedTime, .queuePosition:
      true
    default: false
    }
  }

  /// Whether a first click sorts high to low: numbers and dates do; words
  /// (and the time left and the queue, where small comes first) don't.
  public var sortsDescendingFirst: Bool {
    switch self {
    case .name, .status, .category, .tags, .tracker, .savePath, .eta, .queuePosition: false
    default: true
    }
  }

  /// The columns shown on a new install.
  public static let defaultColumns: [Self] = [
    .name, .size, .progress, .status, .downSpeed, .upSpeed, .eta, .ratio, .category, .tags,
    .addedAt,
  ]
}
