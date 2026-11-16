import Foundation
import HTTPTypes
import Testing
import UmbraAPI

@testable import UmbraKit

/// The Add sheet's calls send what Umbra's API asks for, and read its answers.
@Suite struct AddingActionsTests {
  let connection = Connection(
    baseURL: URL(string: "http://127.0.0.1:7980")!, credential: .apiKey("key"))

  func actions(_ replies: [String: RecordingTransport.Reply] = [:]) -> (
    TorrentActions, RecordingTransport
  ) {
    let transport = RecordingTransport(replies)
    return (TorrentActions(connection: connection, transport: transport), transport)
  }

  @Test func inspectSendsEachKindOfSource() async throws {
    let (actions, transport) = actions(["inspectTorrent": AddSample.torrentPreview])
    let preview = try await actions.inspect(.torrentFile(AddSample.fileBytes))
    _ = try await actions.inspect(.magnet(AddSample.magnet))
    _ = try await actions.inspect(.url("http://127.0.0.1:1/x.torrent"))
    #expect(preview.name == "Sample.Set")
    #expect(preview.files?.count == 3)
    let sent = await transport.sent
    #expect(sent.map(\.path) == Array(repeating: "/torrents/inspect", count: 3))
    #expect(sent[0].torrentFileBytes == AddSample.fileBytes)
    #expect(sent[0].json?["fetchDetails"] == nil)
    // A link asks Umbra to start fetching its details, as the web page does.
    #expect(sent[1].json == ["magnet": AddSample.magnet, "fetchDetails": true])
    #expect(sent[2].json == ["url": "http://127.0.0.1:1/x.torrent", "fetchDetails": true])
  }

  @Test func waitingAndCancellingUseTheHash() async throws {
    let hash = AddSample.magnetHash
    let (actions, transport) = actions(["getWaitingTorrent": AddSample.waiting()])
    let preview = try await actions.waitingTorrent(hash)
    try await actions.cancelWaiting(hash)
    #expect(preview.waiting == true)
    #expect(preview.peers == 3)
    let sent = await transport.sent
    #expect(sent.map(\.method) == [.get, .delete])
    #expect(sent.map(\.path) == ["/torrents/inspect/\(hash)", "/torrents/inspect/\(hash)"])
  }

  @Test func addSendsTheChoices() async throws {
    let (actions, transport) = actions(["addTorrent": AddSample.added()])
    let result = try await actions.add(.magnet(AddSample.magnet), paused: true)
    _ = try await actions.add(
      .torrentFile(AddSample.fileBytes), category: "films", tags: ["a", "b"],
      filePriorities: [.normal, .skip])
    #expect(result.hash == AddSample.fileHash)
    #expect(result.alreadyAdded == false)
    let sent = await transport.sent
    #expect(sent.allSatisfy { $0.method == .post && $0.path == "/torrents" })
    // Exactly what the web page sends for "Add now" on a magnet, paused.
    #expect(sent[0].json == ["magnet": AddSample.magnet, "tags": [String](), "paused": true])
    #expect(sent[1].torrentFileBytes == AddSample.fileBytes)
    #expect(sent[1].json?["category"] as? String == "films")
    #expect(sent[1].json?["tags"] as? [String] == ["a", "b"])
    #expect(sent[1].json?["paused"] as? Bool == false)
    #expect(sent[1].json?["filePriorities"] as? [String] == ["normal", "skip"])
    #expect(sent[1].json?["savePath"] == nil)
  }

  @Test func aWebAddressIsNeverAddedDirectly() async throws {
    let (actions, transport) = actions()
    await #expect(throws: UmbraError.unexpectedAnswer) {
      _ = try await actions.add(.url("http://127.0.0.1:1/x.torrent"))
    }
    #expect(await transport.sent.isEmpty)
  }

  @Test func aRefusalCarriesUmbrasWords() async throws {
    let (actions, _) = actions([
      "addTorrent": .error(.serviceUnavailable, code: "engine_down", message: "The engine is off.")
    ])
    await #expect(throws: UmbraError(code: "engine_down", message: "The engine is off.")) {
      _ = try await actions.add(.magnet(AddSample.magnet))
    }
  }

  @Test func saveFoldersReadTheDownloadsSettings() async throws {
    let (actions, _) = actions(["getDownloadsSettings": AddSample.folders])
    let folders = try await actions.saveFolders()
    #expect(folders.categoryNames == ["films", "books"])
    #expect(folders.folder(for: "") == "/data/downloads")
    #expect(folders.folder(for: "films") == "/data/films")
    // A category with no folder of its own saves in the default one.
    #expect(folders.folder(for: "books") == "/data/downloads")
    #expect(SaveFolders(defaultFolder: "").folder(for: "") == nil)
  }
}

/// Telling magnet links from web addresses, only to pick the field.
@Suite struct AddLinkTests {
  @Test func recognisesMagnetLinksAndWebAddresses() {
    #expect(AddLink.input(from: "  \(AddSample.magnet)\n") == .magnet(AddSample.magnet))
    #expect(AddLink.input(from: "MAGNET:?xt=1") == .magnet("MAGNET:?xt=1"))
    #expect(AddLink.input(from: "https://127.0.0.1/a") == .url("https://127.0.0.1/a"))
    #expect(AddLink.input(from: "http://") == nil)
    #expect(AddLink.input(from: "http://a b") == nil)
    #expect(AddLink.input(from: "ftp://127.0.0.1/a.torrent") == nil)
    #expect(AddLink.input(from: "hello") == nil)
  }
}
