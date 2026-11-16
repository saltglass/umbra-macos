import AppKit
import SwiftUI
import UmbraKit

/// The torrent list: AppKit's table, shown in SwiftUI.
///
/// AppKit, not SwiftUI's `Table`: measured on 2026-11-12, SwiftUI's table
/// lost the selection and the scroll position as the list changed every
/// second. `TorrentTableController` does the work; this only passes
/// values in and the person's choices out.
///
/// Later parts of the window plug in through the closures (all optional):
/// the right-click menu, double-click, and Space and Delete.
struct TorrentTable: NSViewRepresentable {
  /// The rows to show, in order.
  var rows: [TorrentRow]
  /// The selected hashes (two-way).
  var selection: Set<String>
  var sort: TorrentSort
  /// Changes when the filter or search changes; the list then starts from the top.
  var resetKey: String
  /// Where AppKit remembers the columns (order, widths, hidden); nil for
  /// pictures of the view, so they never depend on this Mac's choices.
  var autosaveName: String? = "TorrentList"

  /// The person selected rows.
  var onSelect: (Set<String>) -> Void
  /// The person clicked a column header; the new sort.
  var onSort: (TorrentSort) -> Void

  /// The right-click menu for these selected torrents; nil shows none.
  var menuProvider: ((Set<String>) -> NSMenu?)?
  /// A row was double-clicked (its hash).
  var onDoubleClick: ((String) -> Void)?
  /// Space or Delete was pressed with these selected; return true if handled.
  var onKeyCommand: ((TorrentListKey, Set<String>) -> Bool)?

  func makeCoordinator() -> TorrentTableController {
    TorrentTableController(autosaveName: autosaveName)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let controller = context.coordinator
    controller.owner = self
    controller.update(rows: rows, selection: selection, sort: sort, resetKey: resetKey)
    return controller.scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    let controller = context.coordinator
    controller.owner = self
    controller.update(rows: rows, selection: selection, sort: sort, resetKey: resetKey)
  }
}
