#if DEBUG
  import SwiftUI
  import UmbraAPI
  import UmbraKit

  /// The Create Torrent sheet's pictures: empty, a folder with its preview,
  /// a refusal, creating (progress) and done. Made-up answers; nothing is
  /// asked of Umbra, and every address is an invented one.
  @MainActor
  enum CreatingSnapshots {
    static var entries: [SnapshotEntry] {
      [
        entry("create-empty", height: 500) { _ in },
        entry("create-folder", height: 530) { model in
          model.showFixture(path: folder, preview: .ready(preview))
          model.trackersText =
            "udp://tracker.example.org:6969/announce\nhttps://tracker.example.org/announce\n\nudp://backup.example.org:80"
          model.comment = "Made for the family"
        },
        entry("create-refused", height: 520) { model in
          model.showFixture(
            path: "/Users/alex/.hidden-stuff",
            preview: .refused(
              "Hidden files and folders (names starting with a dot) can't be shared."))
        },
        entry("create-refused-tracker", height: 580) { model in
          model.trackersText = "tracker.example"
          model.showFixture(
            path: folder, preview: .ready(preview),
            problems: [
              .trackers:
                "tracker.example isn't a tracker's address (they start with http://, https:// or udp://)."
            ])
        },
        entry("create-creating", height: 570) { model in
          model.showFixture(
            path: folder, preview: .ready(preview),
            creation: record(state: .reading, read: 18_200_000_000))
        },
        entry("create-queued", height: 570) { model in
          model.showFixture(
            path: folder, preview: .ready(preview), creation: record(state: .queued))
        },
        entry("create-done", height: 610) { model in
          model.showFixture(
            path: folder, preview: .ready(preview),
            creation: record(
              state: .done, read: 44_342_419_456, seeding: true,
              hash: String(repeating: "e", count: 40)))
        },
        entry("create-failed", height: 590) { model in
          model.showFixture(
            path: folder, preview: .ready(preview),
            creation: record(
              state: .failed, read: 9_000_000_000,
              error:
                "couldn't read the files: Holiday.Photos/IMG_0042.jpg changed while Umbra read it.")
          )
        },
      ]
    }

    private static func entry(
      _ name: String, height: CGFloat, setUp: @escaping @MainActor (CreateTorrentModel) -> Void
    ) -> SnapshotEntry {
      SnapshotEntry(name: name, size: CGSize(width: 520, height: height)) {
        // Never used: pictures don't ask Umbra anything.
        let connection = Connection(
          baseURL: URL(string: "http://127.0.0.1:9")!, credential: .apiKey("snapshot"))
        let model = CreateTorrentModel(actions: CreateTorrentActions(connection: connection))
        setUp(model)
        return AnyView(
          CreateSheet(model: model)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(.background))
      }
    }

    private static let folder = "/Users/alex/Pictures/Holiday.Photos"

    private static let preview = Components.Schemas.CreationPreview(
      name: "Holiday.Photos", files: 1204, size: 44_342_419_456, pieceLength: 16_777_216,
      pieces: 2643)

    private static func record(
      state: Components.Schemas.Creation.statePayload, read: Int64 = 0, seeding: Bool = false,
      error: String? = nil, hash: String? = nil
    ) -> Components.Schemas.Creation {
      .init(
        id: "snapshot", name: "Holiday.Photos", path: folder, state: state, files: 1204,
        size: 44_342_419_456, read: read, pieceLength: 16_777_216, pieces: 2643, _private: false,
        error: error, hash: hash, seeding: seeding, started: Date(timeIntervalSince1970: 0))
    }
  }
#endif
