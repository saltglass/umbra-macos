import AppKit
import SwiftUI
import UmbraKit

/// The menu bar item: an icon that shows the state, and a small panel that
/// opens under it. All the deciding is in `MenuBarSummary`; these views only
/// draw it.
struct MenuBarScene: Scene {
  let model: MenuBarModel

  var body: some Scene {
    MenuBarExtra {
      MenuBarPanel(model: model)
    } label: {
      MenuBarLabel(model: model)
    }
    .menuBarExtraStyle(.window)
  }
}

/// The icon in the menu bar. A symbol only, no text.
struct MenuBarLabel: View {
  let model: MenuBarModel

  var body: some View {
    let icon = model.summary.icon
    Image(systemName: icon.symbol)
      .accessibilityLabel(icon.help)
  }
}

/// The panel with its buttons joined to the app: opening windows, running
/// actions and showing Umbra's refusals.
struct MenuBarPanel: View {
  let model: MenuBarModel
  @Environment(\.openWindow) private var openWindow
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    MenuBarPanelView(
      summary: model.summary, failure: model.failureLine,
      actions: MenuBarPanelActions(
        setSlowMode: { on in Task { model.show(await model.setSlowMode(on)) } },
        pauseAll: { Task { model.show(await model.pauseAll()) } },
        resumeAll: { Task { model.show(await model.resumeAll()) } },
        openVpnSettings: {
          NSApp.activate()
          OpenVpnSettingsAction(openSettings: openSettings)()
        },
        openUmbra: {
          NSApp.activate()
          openWindow(id: "main")
        },
        openSettings: {
          NSApp.activate()
          openSettings()
        },
        quit: { NSApp.terminate(nil) }))
  }
}

/// What the panel's buttons do. Pictures of the panel pass empty ones.
struct MenuBarPanelActions {
  var setSlowMode: (Bool) -> Void = { _ in }
  var pauseAll: () -> Void = {}
  var resumeAll: () -> Void = {}
  var openVpnSettings: () -> Void = {}
  var openUmbra: () -> Void = {}
  var openSettings: () -> Void = {}
  var quit: () -> Void = {}
}

/// The panel itself, top to bottom: the heading and counts, the VPN, the
/// speeds, the active downloads, then the controls.
struct MenuBarPanelView: View {
  let summary: MenuBarSummary
  /// One line in Umbra's words when its last action was refused.
  let failure: String?
  let actions: MenuBarPanelActions

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      heading
      if let vpn = summary.vpn { VpnBlock(vpn: vpn, openSettings: actions.openVpnSettings) }
      if summary.showsSpeeds { speeds }
      if !summary.active.isEmpty { activeList }
      if let failure {
        Label(failure, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.secondary)
          .symbolRenderingMode(.multicolor)
          .fixedSize(horizontal: false, vertical: true)
      }
      Divider()
      controls
    }
    .padding(.horizontal, 14)
    .padding(.top, 14)
    .padding(.bottom, 8)
    .frame(width: 300, alignment: .leading)
  }

  private var heading: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(summary.heading).font(.headline)
      Text(summary.countsLine)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  private var speeds: some View {
    HStack(spacing: 8) {
      SpeedTile(title: "Download", symbol: "arrow.down", value: summary.downSpeed)
      SpeedTile(title: "Upload", symbol: "arrow.up", value: summary.upSpeed)
    }
  }

  private var activeList: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Active")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
      ForEach(summary.active) { torrent in
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 8) {
            Text(torrent.name)
              .lineLimit(1)
              .truncationMode(.middle)
            Spacer(minLength: 0)
            Text(torrent.eta)
              .font(.callout.monospacedDigit())
              .foregroundStyle(.secondary)
              .fixedSize()
          }
          ProgressView(value: torrent.progress)
            .controlSize(.small)
        }
      }
      if let more = summary.moreLine {
        Text(more)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var controls: some View {
    VStack(alignment: .leading, spacing: 0) {
      // The whole row is the button; the switch only shows the state.
      MenuRow(
        title: "Slow Mode", symbol: "tortoise",
        trailing: Toggle("Slow Mode", isOn: .constant(summary.slowMode))
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.mini)
          .allowsHitTesting(false),
        action: { actions.setSlowMode(!summary.slowMode) }
      )
      .accessibilityValue(summary.slowMode ? "On" : "Off")
      .disabled(!summary.slowModeEnabled)
      MenuRow(title: "Pause All", symbol: "pause", action: actions.pauseAll)
        .disabled(!summary.canPauseAll)
      MenuRow(title: "Resume All", symbol: "play", action: actions.resumeAll)
        .disabled(!summary.canResumeAll)
      Divider().padding(.vertical, 4)
      MenuRow(title: "Open Umbra", symbol: "macwindow", action: actions.openUmbra)
      MenuRow(title: "Settings…", symbol: "gearshape", action: actions.openSettings)
      MenuRow(title: "Quit Umbra", symbol: "power", action: actions.quit)
    }
    // Lets the rows' highlight reach the panel's edge, as in a menu.
    .padding(.horizontal, -6)
  }
}

/// The VPN's symbol, title and sentence (the pill's popover says the
/// same), the address peers see, and a button where the VPN needs the person.
private struct VpnBlock: View {
  let vpn: MenuBarSummary.Vpn
  let openSettings: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label {
        Text(vpn.title).font(.subheadline.weight(.semibold))
      } icon: {
        Image(systemName: vpn.symbol).foregroundStyle(vpn.role.color)
      }
      Text(vpn.sentence)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      if let address = vpn.address {
        HStack(spacing: 6) {
          Text("Peers see")
            .foregroundStyle(.secondary)
          Text(address)
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
        }
        .font(.callout)
      }
      if vpn.offersSettings {
        Button("Open VPN Settings…", action: openSettings)
          .controlSize(.small)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 8))
  }
}

/// One of the two speed boxes.
private struct SpeedTile: View {
  let title: String
  let symbol: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Label(title, systemImage: symbol)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.title3.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 8))
    .accessibilityElement(children: .combine)
  }
}

/// A row that looks and acts like a menu item: a symbol, the words, and a
/// highlight under the pointer.
private struct MenuRow<Trailing: View>: View {
  let title: String
  let symbol: String
  let trailing: Trailing
  let action: () -> Void
  @State private var hovering = false
  @Environment(\.isEnabled) private var enabled

  init(
    title: String, symbol: String, trailing: Trailing, action: @escaping () -> Void
  ) {
    self.title = title
    self.symbol = symbol
    self.trailing = trailing
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: symbol)
          .frame(width: 18)
          .foregroundStyle(.secondary)
        Text(title)
        Spacer(minLength: 0)
        trailing
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .contentShape(.rect)
      .background(
        hovering && enabled ? Color.primary.opacity(0.1) : Color.clear,
        in: .rect(cornerRadius: 6)
      )
      .opacity(enabled ? 1 : 0.4)
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 6)
    .onHover { hovering = $0 }
  }
}

extension MenuRow where Trailing == EmptyView {
  fileprivate init(title: String, symbol: String, action: @escaping () -> Void) {
    self.init(title: title, symbol: symbol, trailing: EmptyView(), action: action)
  }
}
