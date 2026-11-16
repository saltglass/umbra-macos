#if DEBUG
  import SwiftUI
  import UmbraAPI
  import UmbraKit

  /// The inspector's pictures: with nothing selected, with several, and
  /// each of its four tabs on believable sample data (a tracker that
  /// failed, a folder whose files differ, and so on).
  @MainActor
  enum InspectorSnapshots {
    private static let size = CGSize(width: 300, height: 700)

    static var entries: [SnapshotEntry] {
      [
        entry("inspector-none") { _, _ in },
        entry("inspector-several") { window, _ in
          let rows = window.visibleRows
          window.selection = [rows[1].id, rows[2].id, rows[4].id]
        },
        entry("inspector-general") { _, inspector in inspector.tab = .general },
        // The torrent's own limits, as rows with an Edit… button.
        entry("inspector-general-limits") { window, inspector in
          inspector.tab = .general
          inspector.showFixture(
            for: window.selectedHashes[0],
            limits: .init(
              ratio: 2, seedingMinutes: 4320, inactiveMinutes: -1, downloadLimitKBs: 0,
              uploadLimitKBs: 1536))
        },
        entry("inspector-general-no-limits") { window, inspector in
          inspector.tab = .general
          inspector.showFixture(
            for: window.selectedHashes[0],
            limits: .init(
              ratio: nil, seedingMinutes: nil, inactiveMinutes: nil, downloadLimitKBs: 0,
              uploadLimitKBs: 0))
        },
        entry("inspector-trackers") { _, inspector in inspector.tab = .trackers },
        entry("inspector-peers") { _, inspector in inspector.tab = .peers },
        entry("inspector-files") { _, inspector in inspector.tab = .files },
        entry("inspector-files-collapsed") { _, inspector in
          inspector.tab = .files
          inspector.toggleFolder("Common.Crawl.Sample.2026-09/data")
        },
        // The inspector inside the whole window, one torrent selected.
        SnapshotEntry(
          name: "window-inspector-general", size: CGSize(width: 1160, height: 720),
          windowFrame: true
        ) {
          let session = Fixtures.session()
          let model = Fixtures.model(session.store)
          model.inspectorShown = true
          model.selection = [shown(in: model).id]
          return AnyView(
            MainWindow(
              session: session, model: model, tableAutosaveName: nil, columnVisibility: .all))
        },
      ]
    }

    /// One picture of the inspector alone. By default one torrent is
    /// selected; `setUp` can change that and the inspector.
    private static func entry(
      _ name: String, setUp: @escaping @MainActor (MainWindowModel, InspectorModel) -> Void
    ) -> SnapshotEntry {
      SnapshotEntry(name: name, size: size) {
        let session = Fixtures.session()
        let window = Fixtures.model(session.store)
        let hash = shown(in: window).id
        // Nothing is selected for the first picture only.
        if name != "inspector-none" { window.selection = [hash] }
        let inspector = InspectorModel(
          window: window, actions: { nil }, now: { Fixtures.now })
        inspector.showFixture(
          for: hash, trackers: trackers, findsPeersElsewhere: true, peers: peers, files: files)
        setUp(window, inspector)
        return AnyView(InspectorView(model: inspector))
      }
    }

    /// The torrent the pictures are about: the first one downloading (so
    /// there is a speed and a time left to show).
    private static func shown(in window: MainWindowModel) -> TorrentRow {
      window.visibleRows.first { $0.kind == .downloading && $0.etaSeconds != nil }
        ?? window.visibleRows[1]
    }

    // MARK: Sample data

    private static var trackers: [Components.Schemas.Tracker] {
      let soon = Fixtures.now.addingTimeInterval(28 * 60)
      return [
        .init(
          url: "udp://tracker.example.org:6969/announce", tier: 0, state: .working, seeds: 142,
          peers: 56, lastAnnounce: Fixtures.now.addingTimeInterval(-90), nextAnnounce: soon),
        .init(
          url: "https://tracker.example.net/announce?passkey=0123", tier: 1, state: .error,
          message: "Unregistered torrent"),
        .init(url: "udp://backup.example.com:1337/announce", tier: 2, state: .notContacted),
      ]
    }

    private static var peers: [Components.Schemas.Peer] {
      [
        .init(
          address: "192.0.2.14:51413", client: "qBittorrent 5.0.2", encrypted: true,
          incoming: false, progress: 1, downSpeed: 3_400_000, upSpeed: 0),
        .init(
          address: "198.51.100.77:6881", client: "Transmission 4.0.6", encrypted: true,
          incoming: true, progress: 0.62, downSpeed: 1_150_000, upSpeed: 220_000),
        .init(
          address: "203.0.113.5:49152", client: "libtorrent 2.0.10", encrypted: false,
          incoming: false, progress: 0.18, downSpeed: 0, upSpeed: 48_000),
        .init(
          address: "[2001:db8::2a]:6881", client: "Deluge 2.1.1", encrypted: true,
          incoming: true, progress: 1, downSpeed: 410_000, upSpeed: 0),
        .init(
          address: "192.0.2.201:30303", client: nil, encrypted: false, incoming: false,
          progress: 0.03, downSpeed: 0, upSpeed: 0),
      ]
    }

    private static var files: [Components.Schemas.TorrentFile] {
      let root = "Common.Crawl.Sample.2026-09"
      let gb: Int64 = 1 << 30
      return [
        .init(
          index: 0, path: "\(root)/README.txt", size: 12_288, done: 12_288, priority: .normal),
        .init(
          index: 1, path: "\(root)/checksums/SHA256SUMS", size: 4_096, done: 4_096,
          priority: .normal),
        .init(
          index: 2, path: "\(root)/checksums/SHA256SUMS.sig", size: 1_024, done: 1_024,
          priority: .normal),
        .init(
          index: 3, path: "\(root)/data/part-0001.warc.gz", size: 2 * gb, done: gb + gb / 4,
          priority: .high),
        .init(
          index: 4, path: "\(root)/data/part-0002.warc.gz", size: 2 * gb, done: gb / 3,
          priority: .normal),
        .init(
          index: 5, path: "\(root)/data/part-0003.warc.gz", size: 2 * gb, done: 0,
          priority: .skip),
        .init(
          index: 6, path: "\(root)/docs/schema.md", size: 38_000, done: 38_000, priority: .normal),
        .init(
          index: 7, path: "\(root)/docs/notes.md", size: 9_500, done: 9_500, priority: .normal),
        .init(
          index: 8, path: "\(root)/samples/sample-a.json", size: 640_000_000, done: 0,
          priority: .skip),
        .init(
          index: 9, path: "\(root)/samples/sample-b.json", size: 710_000_000, done: 0,
          priority: .skip),
      ]
    }
  }
#endif
