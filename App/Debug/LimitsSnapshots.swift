#if DEBUG
  import SwiftUI
  import UmbraAPI
  import UmbraKit

  /// Pictures of the Limits sheet: one torrent with values of its own, a
  /// torrent with none, and several torrents at once. (The category sheet
  /// and the inspector's limits are drawn in their own files.)
  @MainActor
  enum LimitsSnapshots {
    static let size = CGSize(width: 520, height: 540)

    private static let global = Components.Schemas.SeedingSettings(
      ratio: 1.5, seedingMinutes: nil, inactiveMinutes: 600)
    private static let films = Components.Schemas.Category(
      name: "films", folder: "", ratio: 2, downloadLimitKBs: 2048)

    static var entries: [SnapshotEntry] {
      [
        SnapshotEntry(name: "limits-sheet-one", size: size) {
          let model = TorrentLimitsModel.fixture(
            request: LimitsRequest(
              hashes: ["a1"], name: "Common.Crawl.Sample.2026-09", categories: ["films"]),
            own: .init(
              ratio: nil, seedingMinutes: 4320, inactiveMinutes: -1, downloadLimitKBs: 0,
              uploadLimitKBs: 1536),
            hints: LimitHints(global: global, category: films))
          return AnyView(TorrentLimitsSheet(model: model))
        },
        SnapshotEntry(name: "limits-sheet-one-none", size: size) {
          let model = TorrentLimitsModel.fixture(
            request: LimitsRequest(
              hashes: ["a1"], name: "Common.Crawl.Sample.2026-09", categories: [""]),
            own: .init(
              ratio: nil, seedingMinutes: nil, inactiveMinutes: nil, downloadLimitKBs: 0,
              uploadLimitKBs: 0),
            hints: LimitHints(global: global))
          return AnyView(TorrentLimitsSheet(model: model))
        },
        SnapshotEntry(name: "limits-sheet-several", size: CGSize(width: 520, height: 580)) {
          let model = TorrentLimitsModel.fixture(
            request: LimitsRequest(
              hashes: ["a1", "b2", "c3"], name: "Alpha", categories: ["films", "films", "films"]),
            own: nil, hints: LimitHints(global: global, category: films))
          return AnyView(TorrentLimitsSheet(model: model))
        },
        // Several, with some boxes filled in or set from their menus.
        SnapshotEntry(name: "limits-sheet-several-edited", size: CGSize(width: 520, height: 580)) {
          let model = TorrentLimitsModel.fixture(
            request: LimitsRequest(
              hashes: ["a1", "b2", "c3"], name: "Alpha", categories: ["films", "music", ""]),
            own: nil, hints: LimitHints(global: global, mixedCategories: true))
          model.type("2", into: .uploadLimit)
          model.choose(.useDefault, for: .downloadLimit)
          model.type("1.5", into: .ratio)
          model.choose(.noGoal, for: .inactiveTime)
          model.type("abc", into: .seedingTime)
          return AnyView(TorrentLimitsSheet(model: model))
        },
      ]
    }
  }
#endif
