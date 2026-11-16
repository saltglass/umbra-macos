// The Settings window (⌘, or Umbra → Settings…): macOS's own settings
// window, with the pages along its toolbar. The page last shown is
// remembered. See README.md in this folder for how to add a page.

import SwiftUI
import UmbraKit

/// The pages, in the toolbar's order.
enum SettingsPage: String, CaseIterable, Identifiable {
  case general, downloads, speed, queueSeeding, connection, vpn, notifications

  var id: Self { self }

  var title: String {
    switch self {
    case .general: "General"
    case .downloads: "Downloads"
    case .speed: "Speed"
    case .queueSeeding: "Queue & Seeding"
    case .connection: "Connection"
    case .vpn: "VPN"
    case .notifications: "Notifications"
    }
  }

  /// The page's SF Symbol in the toolbar.
  var symbol: String {
    switch self {
    case .general: "gearshape"
    case .downloads: "arrow.down.circle"
    case .speed: "gauge.with.dots.needle.67percent"
    case .queueSeeding: "arrow.up.arrow.down.circle"
    case .connection: "network"
    case .vpn: "lock.shield"
    case .notifications: "bell.badge"
    }
  }
}

struct SettingsWindow: View {
  /// One model per settings group, shared for the app's whole life.
  let models: SettingsModels
  /// What the General page shows (shared with the app's own workings).
  let general: GeneralSettings

  /// The page last shown, remembered across launches.
  @AppStorage(SettingsPage.storageKey) private var page: SettingsPage = .downloads

  var body: some View {
    TabView(selection: $page) {
      ForEach(SettingsPage.allCases) { page in
        Tab(page.title, systemImage: page.symbol, value: page) {
          content(of: page)
        }
      }
    }
  }

  @ViewBuilder
  private func content(of page: SettingsPage) -> some View {
    switch page {
    case .general:
      GeneralPage(settings: general)
    case .downloads:
      DownloadsPage(
        downloads: models.model(for: .downloads), seeding: models.model(for: .seeding))
    case .speed:
      SpeedPage(speed: models.model(for: .speed))
    case .queueSeeding:
      QueueSeedingPage(queue: models.model(for: .queue), seeding: models.model(for: .seeding))
    case .connection:
      ConnectionPage(model: models.model(for: .connection))
    case .notifications:
      NotificationsPage(model: models.model(for: .notifications))
    case .vpn:
      // Always there for the app's own session; the VPN has its own model,
      // not a settings group (see VpnPage.swift).
      if let vpn = models.vpn {
        VpnPage(model: vpn)
      }
    }
  }
}
