import Foundation
import UmbraAPI

/// The Mac list's own column choices. The person can change them (right-
/// click a column header); AppKit remembers their choice on this Mac.
extension TorrentColumn {
  /// The columns shown the first time the window opens. Fewer than the web
  /// page's: category and tags are a click away in the sidebar.
  public static let macDefaultColumns: [Self] = [
    .name, .size, .progress, .status, .downSpeed, .upSpeed, .eta, .ratio, .addedAt,
  ]

  /// Every column in the order they first appear: the shown ones, then the rest.
  public static var macColumnOrder: [Self] {
    macDefaultColumns + allCases.filter { !macDefaultColumns.contains($0) }
  }

  /// The name can't be hidden: without it a row means nothing.
  public var canHide: Bool { self != .name }

  /// A first width (in points) that fits the column's usual content.
  public var defaultWidth: Double {
    switch self {
    case .name: 320
    case .progress: 100
    case .status: 112
    case .savePath: 220
    case .tracker: 150
    case .tags: 120
    case .addedAt, .completedAt: 90
    case .category, .downloaded, .uploaded, .seedTime: 84
    case .downSpeed, .upSpeed: 72
    case .size: 64
    case .eta, .seeds, .peers, .queuePosition: 52
    case .ratio: 44
    }
  }

  /// The narrowest a column can be dragged.
  public var minimumWidth: Double { self == .name ? 120 : 40 }
}
