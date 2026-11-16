import Foundation
import Testing
import UmbraAPI

@testable import UmbraKit

/// Create Torrent against a real Umbra on 127.0.0.1, in a temporary data
/// folder (never the real one), with no network beyond this Mac.
extension HelperIntegrationTests {
  /// A folder outside the download folders, made into a torrent with
  /// seeding on, as the app's Create Torrent sheet does it: it is listed,
  /// complete, seeding from where it is, and marked as made from the
  /// person's own files (so the Remove alert can say so). The files are
  /// left where they were, untouched. This also shows the app's real
  /// helper settings let it share from anywhere but Umbra's data folder.
  @Test func aTorrentMadeFromOwnFilesIsMarkedAndLeavesThemInPlace() async throws {
    try await withSupervisor { supervisor, environment in
      let connection = try await supervisor.start()
      let client = connection.makeClient()

      // Two small made-up files, in a temporary folder of their own.
      let outside = try makeTempFolder()
      defer { try? FileManager.default.removeItem(at: outside) }
      let shared = outside.appending(path: "Holiday Photos", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
      let beach = shared.appending(path: "beach.jpg")
      let pier = shared.appending(path: "pier.jpg")
      try Data(repeating: 0x42, count: 200_000).write(to: beach)
      try Data(repeating: 0x17, count: 70_000).write(to: pier)
      let before = try Self.fileNumber(beach)

      // Not in the data folder, and not in any download folder.
      let downloads = try await client.getDownloadsSettings().ok.body.json
      let folder = downloads.folder.isEmpty ? (downloads.defaultFolder ?? "") : downloads.folder
      #expect(!folder.isEmpty)
      let sharedPath = shared.path(percentEncoded: false)
      #expect(!sharedPath.hasPrefix(folder))
      #expect(!sharedPath.hasPrefix(environment.dataFolder.path(percentEncoded: false)))

      let actions = CreateTorrentActions(connection: connection)
      let made = try await actions.create(.init(path: sharedPath, seed: true))
      #expect(made.name == "Holiday Photos")

      // Listed, complete, seeding from the folder it's in, and marked.
      var listed: Components.Schemas.Torrent?
      let appeared = await eventuallyAsync {
        listed = try? await client.listTorrents().ok.body.json.torrents.first {
          $0.name == "Holiday Photos"
        }
        return listed?.progress == 1
      }
      #expect(appeared, "the made torrent never showed up complete")
      let torrent = try #require(listed)
      #expect(torrent.madeFromOwnFiles == true)
      #expect(torrent.state == .seeding || torrent.state == .queued)
      #expect(
        URL(filePath: torrent.savePath).standardizedFileURL.path
          == outside.standardizedFileURL.path)

      // The Remove alert reads it from the same list.
      let row = TorrentRow(torrent, now: Date())
      #expect(row.madeFromOwnFiles)
      let alert = try #require(RemoveConfirmation(TorrentSelection([row])))
      #expect(alert.ownFilesCount == 1)

      // The files are still there, the same files, unchanged.
      #expect(try Self.fileNumber(beach) == before)
      #expect(try Data(contentsOf: beach) == Data(repeating: 0x42, count: 200_000))
      #expect(try Data(contentsOf: pier) == Data(repeating: 0x17, count: 70_000))
    }
  }

  /// The file's number on its disk: the same number means the same file,
  /// not a copy put in its place.
  static func fileNumber(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(
      atPath: url.path(percentEncoded: false))
    return try #require((attributes[.systemFileNumber] as? NSNumber)?.intValue)
  }
}
