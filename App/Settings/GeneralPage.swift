// Settings → General: things about the app itself, not about Umbra's
// server. Sections: "Opening torrents", "Notifications", "Power",
// "Startup" and "Backup". None is an Umbra settings group, so the first four
// work whether or not Umbra is running (the switches are remembered in the
// app's own settings); "Backup" works while Umbra runs (BackupSection.swift).
//
// More sections go here as small views of their own, one `Section` per topic.

import AppKit
import SwiftUI
import UmbraKit

struct GeneralPage: View {
  private let settings: GeneralSettings

  /// The real thing by default; pictures pass models over fakes.
  init(settings: GeneralSettings) {
    self.settings = settings
  }

  var body: some View {
    Form {
      OpeningTorrentsSection(model: settings.opening)
      NotificationsSection(model: settings.notifications)
      PowerSection(model: settings.keepAwake)
      StartupSection(model: settings.loginItem)
      BackupSection(model: settings.backup)
    }
    .formStyle(.grouped)
    .frame(width: SettingsMetrics.width)
    .frame(minHeight: 260, idealHeight: SettingsMetrics.generalHeight)
    .onAppear { refresh() }
    // Another app may have taken over, or the person may have changed
    // something in System Settings, while Settings was away.
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    {
      _ in refresh()
    }
  }

  private func refresh() {
    settings.opening.refresh()
    settings.loginItem.refresh()
    Task { await settings.notifications.refresh() }
  }
}

/// "Opening torrents": is Umbra the app for .torrent files and magnet
/// links, and a button to make it so.
private struct OpeningTorrentsSection: View {
  let model: DefaultAppModel

  var body: some View {
    Section {
      row("Torrent files", help: "Files ending in .torrent.", kind: .torrentFiles)
      row("Magnet links", help: "Links that start with magnet:.", kind: .magnetLinks)
    } header: {
      Text("Opening torrents")
    } footer: {
      Text(
        "macOS may ask you to confirm. Until Umbra is signed, macOS can forget this after a new build."
      )
      .font(.callout)
    }
  }

  private func row(_ title: String, help: String, kind: OpeningKind) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      LabeledContent {
        Button("Make Default") {
          Task { await model.makeDefault(kind) }
        }
        .disabled(!model.canMakeDefault(kind))
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
          Text(model.status(for: kind))
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }
      .help(help)
      SettingsProblem(message: model.problem(for: kind))
        .font(.callout)
    }
  }
}

/// "Notifications": one switch for each kind, and what to do if macOS has
/// turned Umbra's notifications off.
private struct NotificationsSection: View {
  let model: NotificationPreferences

  var body: some View {
    Section {
      row("A download finishes", .finished)
      row("A torrent has a problem", .problem)
      row("The VPN goes down or comes back", .vpn)
      if model.isRefused {
        VStack(alignment: .leading, spacing: 6) {
          Text(NotificationPreferences.refusedMessage)
            .font(.callout)
            .foregroundStyle(.secondary)
          Button(NotificationPreferences.openSettingsButton) { model.openSystemSettings() }
        }
      }
    } header: {
      Text("Notifications")
    }
  }

  private func row(_ title: String, _ kind: NotificationKind) -> some View {
    Toggle(
      title,
      isOn: Binding(
        get: { model.isOn(kind) },
        set: { on in Task { await model.set(kind, on: on) } }))
  }
}

/// "Power": keep the Mac from sleeping while torrents download.
private struct PowerSection: View {
  @Bindable var model: KeepAwakePreferences

  var body: some View {
    Section {
      Toggle("Keep the Mac awake while downloading", isOn: $model.enabled)
      Toggle("Also on battery", isOn: $model.alsoOnBattery)
        .disabled(!model.enabled)
    } header: {
      Text("Power")
    } footer: {
      Text("The display can still sleep. Seeding alone never keeps the Mac awake.")
        .font(.callout)
    }
  }
}

/// "Startup": open Umbra when the person logs in.
private struct StartupSection: View {
  let model: LoginItemModel

  var body: some View {
    Section {
      VStack(alignment: .leading, spacing: 6) {
        Toggle(
          "Open Umbra at login",
          isOn: Binding(get: { model.isOn }, set: { model.set($0) })
        )
        .disabled(!model.canChange)
        if let note = model.note {
          Text(note)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        if model.needsApproval {
          Button(LoginItemModel.openSettingsButton) { model.openSystemSettings() }
        }
        SettingsProblem(message: model.problem)
          .font(.callout)
      }
    } header: {
      Text("Startup")
    }
  }
}
