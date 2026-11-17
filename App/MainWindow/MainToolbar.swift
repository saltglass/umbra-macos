import SwiftUI
import UmbraKit

/// The toolbar's buttons: Pause, Resume, Remove and the slow mode switch,
/// with Add first, then the VPN pill. (The inspector's button is
/// `InspectorToggle`, which sits above the inspector.) Only buttons that work appear (Add opens
/// the Add sheet, in App/Adding). The sidebar button and the search field are the
/// system's own.
struct MainToolbar: ToolbarContent {
  let model: MainWindowModel
  /// Nil while Umbra isn't connected: the buttons are then dimmed.
  let actions: TorrentActions?
  /// The VPN pill's words.
  let vpn: VpnSummary
  /// Asks Umbra to check the VPN again.
  let onCheckVpn: (() async -> Void)?
  /// Asks first, then starts without a VPN (the pill's popover).
  var onStartWithoutVpn: ((StartWithoutVpnConfirmation) async -> Void)?
  /// Opens the Remove alert; nil in pictures of the view.
  @Environment(\.torrentCommands) private var commands

  @Environment(\.addTorrents) private var adding

  var body: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
      // The Add sheet; also File → Open Torrent… and Add Magnet Link….
      Button("Add", systemImage: "plus") { adding?.showSheet() }
        .help("Add a torrent from a file, a magnet link or a web address")
        .disabled(actions == nil || adding?.canOpen != true)
    }
    ToolbarItemGroup(placement: .primaryAction) {
      Button("Pause", systemImage: "pause.fill") { run(.pause) }
        .help("Pause the selected torrents")
        .disabled(!model.canPause(with: actions))
      Button("Resume", systemImage: "play.fill") { run(.resume) }
        .help("Resume the selected torrents")
        .disabled(!model.canResume(with: actions))
      // Opens the Remove alert, which asks before anything is deleted.
      Button("Remove", systemImage: "trash") { commands?.run(.remove) }
        .help("Remove the selected torrents…")
        .disabled(!model.canAct(with: actions))
    }
    ToolbarItem(placement: .primaryAction) {
      // A switch that stays pressed while slow mode is on, as the system's
      // own toolbar toggles do.
      Toggle("Slow Mode", systemImage: "tortoise", isOn: slowMode)
        .toggleStyle(.button)
        .help(
          model.slowMode
            ? "Slow mode is on: using the lower speed limits. Click to go back to full speed."
            : "Slow mode is off. Click to use the lower speed limits set in Settings."
        )
        .disabled(actions == nil)
    }
    ToolbarItem(placement: .primaryAction) {
      VpnPillView(summary: vpn, onCheckAgain: onCheckVpn, onStartWithout: onStartWithoutVpn)
    }
  }

  private var slowMode: Binding<Bool> {
    Binding(
      get: { model.slowMode },
      set: { on in Task { await model.setSlowMode(on, using: actions) } })
  }

  private func run(_ action: TorrentActions.Action) {
    Task { await model.perform(action, using: actions) }
  }
}

/// The button that shows and hides the inspector. It lives in the
/// inspector's own part of the toolbar, at the window's trailing edge.
struct InspectorToggle: View {
  @Bindable var model: MainWindowModel

  var body: some View {
    Button(
      model.inspectorShown ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.trailing"
    ) {
      model.inspectorShown.toggle()
    }
    .help(model.inspectorShown ? "Hide Inspector" : "Show Inspector")
  }
}
