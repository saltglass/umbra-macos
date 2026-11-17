import SwiftUI
import UmbraKit

/// The main window. While Umbra runs: the sidebar, the torrent list and the
/// inspector. While it starts, restarts, saves or has failed: a plain
/// message in their place.
struct MainWindow: View {
  let session: AppSession
  let model: MainWindowModel
  /// Where the list's columns are remembered (nil in pictures of the view).
  var tableAutosaveName: String? = "TorrentList"
  /// The sidebar starts shown (pictures need saying so; see SnapshotRunner).
  var columnVisibility = NavigationSplitViewVisibility.automatic

  var body: some View {
    if SessionScreen.showsList(phase: session.phase, loaded: session.store.loaded) {
      MainSplitView(
        session: session, model: model, tableAutosaveName: tableAutosaveName,
        columnVisibility: columnVisibility)
    } else {
      SessionStateView(phase: session.phase)
        .navigationTitle("Umbra")
    }
  }
}

/// Sidebar | list | inspector (full height), the toolbar and search.
struct MainSplitView: View {
  let session: AppSession
  @Bindable var model: MainWindowModel
  let tableAutosaveName: String?
  @State var columnVisibility: NavigationSplitViewVisibility
  @FocusState private var searchFocused: Bool
  @Environment(\.addTorrents) private var adding
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      SidebarView(model: model, freeSpace: statusBar.freeSpace)
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 320)
    } detail: {
      TorrentListPane(
        model: model, statusBar: statusBar, loaded: session.store.loaded,
        tableAutosaveName: tableAutosaveName,
        banners: StatusBanner.list(
          transfer: session.store.transfer, waking: session.isCheckingVpnAfterWake),
        connectionNote: SessionScreen.note(phase: session.phase, connection: session.store.state),
        onBannerAction: { await perform($0) }
      )
      .toolbar {
        MainToolbar(
          model: model, actions: session.actions, vpn: vpnSummary,
          onCheckVpn: { await checkVpn() },
          onStartWithoutVpn: { await startWithoutVpn($0) })
      }
      .addTorrentSheet(adding, freeSpace: statusBar.freeSpace)
      // Limits… (a torrent's own speed limits and seed goals)
      .limitsSheet(window: model, session: session)
      .createTorrentSheet(adding?.creating)
    }
    // Attached to the whole split view, not the list, so the inspector runs
    // the full height of the window and the list's buttons and VPN pill end
    // at its edge. Its own button sits above it, beside the search field.
    .inspector(isPresented: $model.inspectorShown) {
      InspectorHost(session: session, window: model)
        .inspectorColumnWidth(min: 240, ideal: 280, max: 420)
        .toolbar {
          Spacer()
          InspectorToggle(model: model)
        }
    }
    .navigationTitle(model.title)
    .navigationSubtitle(model.subtitle)
    // The system puts its search field at the window's far edge, which with
    // the inspector open is above the inspector. Tried and dropped (0.1.2):
    // the centre placement (so wide it hid the title and the VPN pill) and a
    // minimised search button (not available on macOS).
    .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search")
    .searchFocused($searchFocused)
    .onChange(of: model.searchFocusRequests) { searchFocused = true }
    .alert(
      model.actionFailure?.title ?? "",
      isPresented: Binding(
        get: { model.actionFailure != nil }, set: { if !$0 { model.actionFailure = nil } }),
      presenting: model.actionFailure
    ) { _ in
      Button("OK") {}
    } message: { failure in
      Text(failure.message)
    }
  }

  private var vpnSummary: VpnSummary {
    VpnSummary(
      transfer: session.store.transfer, status: session.vpnStatus,
      connection: session.store.state, waking: session.isCheckingVpnAfterWake)
  }

  /// "Check Again": Umbra looks at the VPN now; a refusal is shown in the alert.
  private func checkVpn() async {
    do {
      try await session.checkVpnAgain()
    } catch {
      model.actionFailure = ActionFailure(
        title: "Couldn't check the VPN", message: error.message)
    }
  }

  /// A banner's button.
  private func perform(_ action: StatusBanner.Action) async {
    switch action {
    case .checkAgain: await checkVpn()
    case .openVpnSettings: OpenVpnSettingsAction(openSettings: openSettings)()
    case .startWithoutVpn(let question): await startWithoutVpn(question)
    }
  }

  /// "Start Without VPN…": always asks first (Cancel is the default), and
  /// only on a yes asks Umbra to release its hold. Umbra decides; a refusal
  /// is shown in the alert.
  private func startWithoutVpn(_ question: StartWithoutVpnConfirmation) async {
    guard await VpnPrompts.confirmStartWithout(question) else { return }
    do {
      try await session.startWithoutVpn()
    } catch {
      model.actionFailure = ActionFailure(
        title: "Couldn't start without a VPN", message: error.message)
    }
  }

  private var statusBar: StatusBarInfo {
    StatusBarInfo(
      transfer: session.store.transfer, connection: session.store.state,
      listenPort: session.listenPort, vpn: session.vpnStatus)
  }
}
