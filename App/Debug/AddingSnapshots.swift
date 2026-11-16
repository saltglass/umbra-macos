#if DEBUG
  import SwiftUI
  import UmbraAPI
  import UmbraKit

  /// The Add sheet's pictures: empty, a .torrent file with its files, a
  /// magnet link fetching its details, one already in the list, and a
  /// refusal. Made-up answers; nothing is asked of Umbra.
  @MainActor
  enum AddingSnapshots {
    static var entries: [SnapshotEntry] {
      [
        entry("add-empty", height: 250) { _ in },
        entry("add-torrent-file", height: 560) { model in
          model.showFixture(
            [("common-crawl-sample-2026-09.torrent", .torrentFile(Data()), .ready(crawl))],
            folders: folders)
          model.addTag("open-data")
          model.toggleFolder("Common.Crawl.Sample.2026-09/wat")
          if let wat = model.visibleNodes.first(where: { $0.name == "wat" }) { model.click(wat) }
        },
        entry("add-magnet-waiting", height: 350) { model in
          let link = "magnet:?xt=urn:btih:\(String(repeating: "c", count: 40))&dn=Debian"
          model.showFixture(
            [(link, .magnet(link), .waiting(waiting))], link: link, folders: folders)
        },
        entry("add-duplicate", height: 380) { model in
          model.showFixture(
            [
              (
                "ubuntu-26.04-desktop-amd64.iso.torrent", .torrentFile(Data()),
                .duplicate(dup, existing)
              )
            ],
            folders: folders)
        },
        entry("add-refused", height: 310) { model in
          let link = "https://127.0.0.1/files/nothing-here.torrent"
          model.showFixture(
            [
              (
                link, .url(link),
                .refused("That address answered 404 Not Found: there's no .torrent file there.")
              )
            ],
            link: link, folders: folders)
        },
      ]
    }

    private static func entry(
      _ name: String, height: CGFloat, setUp: @escaping @MainActor (AddTorrentModel) -> Void
    ) -> SnapshotEntry {
      SnapshotEntry(name: name, size: CGSize(width: 520, height: height)) {
        // Never used: pictures don't ask Umbra anything.
        let connection = Connection(
          baseURL: URL(string: "http://127.0.0.1:9")!, credential: .apiKey("snapshot"))
        let model = AddTorrentModel(
          actions: TorrentActions(connection: connection),
          categories: ["datasets", "linux-isos", "movies"], tags: ["open-data", "linux"])
        setUp(model)
        return AnyView(
          AddSheet(model: model, freeSpace: "412 GB free")
            .frame(maxHeight: .infinity, alignment: .top)
            .background(.background))
      }
    }

    private static let folders = SaveFolders(
      defaultFolder: "/Users/alex/Downloads/Umbra",
      categoryNames: ["datasets", "linux-isos", "movies"],
      categoryFolders: ["datasets": "/Volumes/Media/Torrents/datasets"])

    private static let crawl = AddTorrentModel.Preview(
      hash: String(repeating: "a", count: 40), name: "Common.Crawl.Sample.2026-09",
      detailsKnown: true, size: 6_764_577_609,
      files: [
        file("warc/CC-MAIN-20260901-00000.warc.gz", 1_181_116_006),
        file("warc/CC-MAIN-20260901-00001.warc.gz", 1_181_116_006),
        file("warc/CC-MAIN-20260901-00002.warc.gz", 1_073_741_824),
        file("wat/CC-MAIN-20260901-00000.wat.gz", 1_288_490_188),
        file("wat/CC-MAIN-20260901-00001.wat.gz", 1_181_116_006),
        file("wet/CC-MAIN-20260901-00000.wet.gz", 858_993_459),
        file("README.md", 4_096),
        file("LICENSE", 1_024),
      ], _private: false,
      trackers: ["udp://tracker.invalid/a", "udp://tracker.invalid/b", "udp://tracker.invalid/c"])

    private static func file(_ path: String, _ size: Int64) -> Components.Schemas.PreviewFile {
      .init(path: "Common.Crawl.Sample.2026-09/\(path)", size: size)
    }

    private static let waiting = AddTorrentModel.Preview(
      hash: String(repeating: "c", count: 40), name: "debian-13.2.0-amd64-netinst.iso",
      detailsKnown: false, _private: false, trackers: [], waiting: true, peers: 3)

    private static let existing = Components.Schemas.ExistingTorrent(
      hash: String(repeating: "d", count: 40), name: "ubuntu-26.04-desktop-amd64.iso",
      state: .seeding, newTrackers: ["https://tracker.invalid/announce"])

    private static let dup = AddTorrentModel.Preview(
      hash: String(repeating: "d", count: 40), name: "ubuntu-26.04-desktop-amd64.iso",
      detailsKnown: true, size: 6_442_450_944,
      files: [.init(path: "ubuntu-26.04-desktop-amd64.iso", size: 6_442_450_944)],
      _private: false, trackers: ["https://tracker.invalid/announce"], existing: existing)
  }
#endif
