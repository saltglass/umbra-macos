import Foundation
import UmbraAPI

/// How each filter reads in the Mac app's sidebar and window title.
extension TorrentFilter {
  /// The window's title while this filter is chosen, and its sidebar label.
  public var title: String {
    switch self {
    case .status(.all): "All Torrents"
    case .status(let status): status.label
    case .category(let name): name.isEmpty ? "No Category" : name
    case .tag(let name): name
    case .tracker(let host): host.isEmpty ? "No Tracker" : host
    }
  }

  /// The SF Symbol beside it in the sidebar.
  public var symbolName: String {
    switch self {
    case .status(.all): "tray.full"
    case .status(.downloading): "arrow.down.circle"
    case .status(.seeding): "arrow.up.circle"
    case .status(.paused): "pause.circle"
    case .status(.queued): "clock"
    case .status(.errors): "exclamationmark.triangle"
    case .category: "folder"
    case .tag: "tag"
    case .tracker: "globe"
    }
  }
}

/// One row of the sidebar: a filter and how many torrents it holds.
public struct SidebarItem: Identifiable, Equatable, Sendable {
  public let filter: TorrentFilter
  public let count: Int
  /// Drawn as a warning (the Errors row, while anything is in it).
  public let isAlert: Bool

  public var id: String { filter.key }
  public var title: String { filter.title }
  public var symbolName: String { filter.symbolName }
}

/// One group of sidebar rows. The status rows come first with no heading.
public struct SidebarSection: Identifiable, Equatable, Sendable {
  public let id: String
  /// The heading ("Categories"); nil for the status rows.
  public let title: String?
  public let items: [SidebarItem]

  /// The sidebar for these counts, following the web page's rules
  /// (`Sidebar.tsx`): the status rows always; categories and tags when
  /// there are any; trackers only from two on, since one tracker for
  /// everything filters nothing.
  public static func all(for counts: TorrentCounts) -> [SidebarSection] {
    let status = StatusFilter.allCases.map { status in
      let count = counts.status[status] ?? 0
      return SidebarItem(
        filter: .status(status), count: count, isAlert: status == .errors && count > 0)
    }
    var sections = [SidebarSection(id: "status", title: nil, items: status)]
    func group(
      _ id: String, _ title: String, _ values: [String: Int], minimum: Int,
      _ make: (String) -> TorrentFilter
    ) {
      guard values.count >= minimum else { return }
      let items = TorrentCounts.sortedKeys(values).map {
        SidebarItem(filter: make($0), count: values[$0] ?? 0, isAlert: false)
      }
      sections.append(SidebarSection(id: id, title: title, items: items))
    }
    group("categories", "Categories", counts.categories, minimum: 1) { .category($0) }
    group("tags", "Tags", counts.tags, minimum: 1) { .tag($0) }
    group("trackers", "Trackers", counts.trackers, minimum: 2) { .tracker($0) }
    return sections
  }
}
