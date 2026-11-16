import SwiftUI
import UmbraKit

/// The middle of the window: the torrent list (or why it's empty) above
/// the status bar.
struct TorrentListPane: View {
  @Bindable var model: MainWindowModel
  let statusBar: StatusBarInfo
  /// False until Umbra has sent the first list.
  let loaded: Bool
  let tableAutosaveName: String?
  /// The notices above the list.
  var banners: [StatusBanner] = []
  /// The quiet "Reconnecting…" line; nil when all is well.
  var connectionNote: String?
  /// Carries out a banner's button; nil in pictures of the view.
  var onBannerAction: ((StatusBanner.Action) async -> Void)?
  /// What the right-click menu, Space, Delete and double-click do; nil in
  /// pictures of the view.
  @Environment(\.torrentCommands) private var commands
  /// Where dropped .torrent files and magnet links go; nil in pictures of the view.
  @Environment(\.addTorrents) private var adding

  var body: some View {
    VStack(spacing: 0) {
      StatusBanners(
        banners: banners, connectionNote: connectionNote,
        onAction: { await onBannerAction?($0) })
      TorrentTable(
        rows: model.visibleRows,
        selection: model.selection,
        sort: model.sort,
        resetKey: "\(model.filter.key)\n\(model.searchText)",
        autosaveName: tableAutosaveName,
        onSelect: { model.selection = $0 },
        onSort: { model.sort = $0 },
        menuProvider: { commands?.contextMenu(for: $0) },
        onDoubleClick: { _ in commands?.openInspector() },
        onKeyCommand: { key, _ in commands?.handle(key) ?? false }
      )
      .overlay { emptyState }
      Divider()
      StatusBarView(info: statusBar)
    }
    // Dropping .torrent files or a magnet link here opens the Add sheet.
    .dropsTorrents(onto: adding)
    // The Category menu lists the categories Umbra has set up: ask when
    // Umbra connects and again whenever it says its settings changed.
    .task(id: "\(commands?.connected == true) \(model.settingsChangeCount)") {
      await model.refreshCategories(using: commands?.actions)
    }
  }

  @ViewBuilder private var emptyState: some View {
    if !loaded {
      ProgressView()
    } else if model.visibleRows.isEmpty {
      if model.searchText.isEmpty {
        ContentUnavailableView(
          "No torrents here", systemImage: model.filter.symbolName,
          description: Text("Nothing matches this filter yet."))
      } else {
        ContentUnavailableView.search(text: model.searchText)
      }
    }
  }
}
