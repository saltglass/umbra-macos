#if DEBUG
  import SwiftUI
  import UmbraAPI
  import UmbraKit

  /// Pictures of the settings pages' contents. The Settings window's own
  /// frame and toolbar draw blank offscreen (Liquid Glass), so only the
  /// pages are drawn. Each page adds its entries here. Values are made up.
  @MainActor
  enum SettingsSnapshots {
    static let size = CGSize(width: SettingsMetrics.width, height: 600)

    static var entries: [SnapshotEntry] {
      [
        // Loaded, with Umbra having just refused "0 downloads at once".
        SnapshotEntry(name: "settings-queue-seeding", size: size) {
          AnyView(
            QueueSeedingPage(
              queue: .init(
                .queue, fixture: .init(maxActiveDownloads: 3, maxActiveSeeds: 0),
                refusal: UmbraError(
                  code: "invalid", message: "Some fields need attention.",
                  fields: ["maxActiveDownloads": "Enter a number from 1 to 50."])),
              seeding: .init(
                .seeding, fixture: .init(ratio: 2, seedingMinutes: 10080, inactiveMinutes: nil),
                refusal: UmbraError(
                  code: "internal", message: "Something went wrong. The details are in the log."))
            ))
        },
        SnapshotEntry(
          name: "settings-queue-seeding-not-connected",
          size: CGSize(width: SettingsMetrics.width, height: 300)
        ) {
          AnyView(
            QueueSeedingPage(
              queue: .init(.queue, fixture: nil, phase: .notConnected),
              seeding: .init(.seeding, fixture: nil, phase: .notConnected)))
        },
      ]
    }
  }
#endif
