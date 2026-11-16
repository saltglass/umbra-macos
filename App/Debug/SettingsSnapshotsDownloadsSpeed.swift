#if DEBUG
  import SwiftUI
  import UmbraAPI
  import UmbraKit

  /// Pictures of Settings → Downloads and Settings → Speed, with made-up
  /// values: loaded, with Umbra refusing something, and the category sheet.
  /// What the category sheet pictures share.
  @MainActor
  enum CategorySheetSnapshot {
    static let size = CGSize(width: 520, height: 700)
    /// The global goals, which the empty boxes name as the ones that apply.
    static let seeding = SettingsGroupModel<Components.Schemas.SeedingSettings>(
      .seeding,
      fixture: .init(ratio: 1.5, seedingMinutes: nil, inactiveMinutes: 600))
  }

  @MainActor
  enum SettingsSnapshotsDownloadsSpeed {
    static let size = CGSize(width: SettingsMetrics.width, height: 680)

    typealias Downloads = Components.Schemas.DownloadsSettings

    static func downloads(
      folder: String = "/Users/alex/Movies/Torrents", watch: String = "/Users/alex/Watch"
    ) -> Downloads {
      Downloads(
        folder: folder, defaultFolder: "/Users/alex/Downloads/Umbra",
        incompleteFolder: "/Users/alex/Downloads/Umbra/Partial",
        categories: [
          .init(
            name: "Movies", folder: "/Volumes/Media/Movies", ratio: 2, seedingMinutes: 4320,
            inactiveMinutes: -1, downloadLimitKBs: 2048, uploadLimitKBs: 512),
          .init(name: "Music", folder: ""),
          .init(name: "Shows", folder: "/Users/alex/Movies/Shows"),
        ], lowSpaceWarningGB: 20, watchFolder: watch)
    }

    static let speed = Components.Schemas.SpeedSettings(
      downloadLimitKBs: 0, uploadLimitKBs: 1536, slowMode: true, slowDownloadKBs: 512,
      slowUploadKBs: 128,
      slowModeSchedule: .init(
        enabled: true, days: [1, 2, 3, 4, 5], from: "22:00", to: "07:00"))

    static var entries: [SnapshotEntry] {
      [
        SnapshotEntry(name: "settings-downloads", size: size) {
          AnyView(DownloadsPage(downloads: .init(.downloads, fixture: downloads())))
        },
        // Nothing chosen yet: the default folder is the folder in use; the
        // watch folder and the others are off. Umbra refused a folder.
        SnapshotEntry(name: "settings-downloads-refused", size: size) {
          var empty = downloads(folder: "", watch: "")
          empty.incompleteFolder = ""
          empty.categories = []
          empty.lowSpaceWarningGB = 0
          return AnyView(
            DownloadsPage(
              downloads: .init(
                .downloads, fixture: empty,
                refusal: UmbraError(
                  code: "invalid", message: "Some fields need attention.",
                  fields: ["watchFolder": "That folder doesn't exist."]))))
        },
        SnapshotEntry(
          name: "settings-category-add", size: CategorySheetSnapshot.size
        ) {
          AnyView(
            CategorySheet(
              kind: .add, model: .init(.downloads, fixture: downloads()),
              seeding: CategorySheetSnapshot.seeding))
        },
        // A category with its own limits and goals.
        SnapshotEntry(name: "settings-category-limits", size: CategorySheetSnapshot.size) {
          AnyView(
            CategorySheet(
              kind: .edit(downloads().categories[0]),
              model: .init(.downloads, fixture: downloads()),
              seeding: CategorySheetSnapshot.seeding))
        },
        // The sheet after Umbra said no: it stays open and says why.
        SnapshotEntry(
          name: "settings-category-edit-refused", size: CategorySheetSnapshot.size
        ) {
          AnyView(
            CategorySheet(
              kind: .edit(downloads().categories[0]),
              model: .init(.downloads, fixture: downloads()),
              seeding: CategorySheetSnapshot.seeding,
              refusedAs: CategoryProblems(
                UmbraError(
                  code: "invalid", message: "Some fields need attention.",
                  fields: [
                    "categories.0.folder": "That folder can't be used: it isn't writable.",
                    "categories.0.ratio": "A ratio can't be more than 1000.",
                  ]),
                index: 0)))
        },
        SnapshotEntry(
          name: "settings-speed", size: CGSize(width: SettingsMetrics.width, height: 760)
        ) {
          AnyView(
            SpeedPage(
              speed: .init(
                .speed, fixture: speed,
                refusal: UmbraError(
                  code: "invalid", message: "Some fields need attention.",
                  fields: [
                    "uploadLimitKBs": "Enter a number of 0 or more.",
                    "slowModeSchedule.from": "Enter a time like 22:00.",
                  ]))))
        },
        SnapshotEntry(
          name: "settings-speed-schedule-off",
          size: CGSize(width: SettingsMetrics.width, height: 560)
        ) {
          var off = speed
          off.slowMode = false
          off.downloadLimitKBs = 2048
          off.slowModeSchedule.enabled = false
          return AnyView(SpeedPage(speed: .init(.speed, fixture: off)))
        },
      ]
    }
  }
#endif
