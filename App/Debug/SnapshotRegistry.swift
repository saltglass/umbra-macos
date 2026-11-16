#if DEBUG
  import SwiftUI
  import UmbraKit

  /// One picture `just snapshot` draws: a name (the file is
  /// `<name>-light.png` and `<name>-dark.png`), a size in points, and the
  /// view, built from fixed sample data so every run draws the same thing.
  struct SnapshotEntry {
    let name: String
    let size: CGSize
    /// Draw the whole window, title bar and toolbar included.
    var windowFrame = false
    let makeView: @MainActor () -> AnyView
  }

  /// The views to draw. New views add an entry here.
  @MainActor
  enum SnapshotRegistry {
    static var entries: [SnapshotEntry] {
      [
        // The whole window. Its sidebar draws blank offscreen (Liquid
        // Glass; see SnapshotRunner), so the sidebar has its own entry.
        SnapshotEntry(name: "window", size: CGSize(width: 1160, height: 720), windowFrame: true) {
          Fixtures.window(inspector: false)
        },
        SnapshotEntry(
          name: "window-inspector", size: CGSize(width: 1160, height: 720), windowFrame: true
        ) {
          Fixtures.window(inspector: true)
        },
        SnapshotEntry(name: "sidebar", size: CGSize(width: 230, height: 700)) {
          AnyView(SidebarView(model: Fixtures.model(), freeSpace: "412 GB free"))
        },
        SnapshotEntry(name: "list-selected", size: CGSize(width: 1000, height: 520)) {
          let model = Fixtures.model()
          let rows = model.visibleRows
          model.selection = [rows[1].id, rows[2].id, rows[4].id]
          return AnyView(Fixtures.listPane(model))
        },
        SnapshotEntry(name: "list-empty", size: CGSize(width: 800, height: 400)) {
          let model = Fixtures.model()
          model.filter = .tag("nothing-has-this")
          return AnyView(Fixtures.listPane(model))
        },
        SnapshotEntry(name: "list-search-empty", size: CGSize(width: 800, height: 400)) {
          let model = Fixtures.model()
          model.searchText = "zzz"
          return AnyView(Fixtures.listPane(model))
        },
        SnapshotEntry(name: "status-bar", size: CGSize(width: 1000, height: 26)) {
          AnyView(StatusBarView(info: Fixtures.statusBar()))
        },
        SnapshotEntry(name: "status-bar-narrow", size: CGSize(width: 520, height: 26)) {
          AnyView(StatusBarView(info: Fixtures.statusBar()))
        },
        SnapshotEntry(name: "window-starting", size: CGSize(width: 640, height: 360)) {
          AnyView(MainWindow(session: Fixtures.session(phase: .starting), model: Fixtures.model()))
        },
        SnapshotEntry(name: "window-failed", size: CGSize(width: 640, height: 360)) {
          AnyView(
            MainWindow(
              session: Fixtures.session(
                phase: .failed(
                  message:
                    "Umbra's server stopped while starting (exit code 1). The end of its log is below.",
                  logTail: ["umbra started", "the engine can't start: port 6881 in use"])),
              model: Fixtures.model()))
        },
      ] + ActionSnapshots.entries + InspectorSnapshots.entries
        + StatusSnapshots.entries + MenuBarSnapshots.entries + AddingSnapshots.entries
        + CreatingSnapshots.entries
        + SettingsSnapshots.entries
        + SettingsSnapshotsConnectionNotifications.entries
        + SettingsSnapshotsDownloadsSpeed.entries + SettingsSnapshotsVpn.entries
        + SettingsSnapshotsGeneral.entries + LimitsSnapshots.entries
        + LogsSnapshots.entries + AboutSnapshots.entries
    }
  }

  /// Fixed sample data: the stress feed's first list for seed 1.
  @MainActor
  enum Fixtures {
    /// 12 November 2026, 14:30 UTC.
    static let now = Date(timeIntervalSince1970: 1_794_493_800)

    static func feed() -> FeedState {
      let stress = StressFeed(seed: 1, start: now)
      var feed = FeedState()
      feed.applySnapshot(stress.snapshot)
      feed.transfer = stress.transfer
      feed.connection = .live
      return feed
    }

    static func session(phase: AppSession.Phase = .running) -> AppSession {
      AppSession(fixture: TorrentStore.fixture(feed()), phase: phase, listenPort: 6881)
    }

    /// A window model with nothing remembered: its settings are thrown
    /// away each time, so pictures never depend on this Mac's choices.
    static func model(_ store: TorrentStore = .fixture(feed())) -> MainWindowModel {
      let suite = "com.saltglass.umbra.snapshots"
      let defaults = UserDefaults(suiteName: suite)!
      defaults.removePersistentDomain(forName: suite)
      return MainWindowModel(store: store, defaults: defaults, now: { now })
    }

    /// The whole window on the stress list, three rows selected.
    static func window(inspector: Bool) -> AnyView {
      let session = session()
      let model = model(session.store)
      model.inspectorShown = inspector
      let rows = model.visibleRows
      model.selection = [rows[1].id, rows[2].id, rows[4].id]
      return AnyView(
        MainWindow(
          session: session, model: model, tableAutosaveName: nil, columnVisibility: .all))
    }

    static func listPane(_ model: MainWindowModel) -> some View {
      TorrentListPane(model: model, statusBar: statusBar(), loaded: true, tableAutosaveName: nil)
    }

    static func statusBar() -> StatusBarInfo {
      let session = session()
      return StatusBarInfo(
        transfer: session.store.transfer, connection: session.store.state,
        listenPort: session.listenPort, vpn: nil)
    }
  }
#endif
