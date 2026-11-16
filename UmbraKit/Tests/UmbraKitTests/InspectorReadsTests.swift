import Foundation
import Testing
import UmbraAPI

@testable import UmbraKit

/// The inspector's reads send the right request and read the answer; a
/// refusal comes back as Umbra's own words.
@Suite("reading a torrent's details") struct InspectorReadsTests {
  let connection = Connection(
    baseURL: URL(string: "http://127.0.0.1:7980")!, credential: .apiKey("key"))

  func actions(_ replies: [String: RecordingTransport.Reply]) -> (
    TorrentActions, RecordingTransport
  ) {
    let transport = RecordingTransport(replies)
    return (TorrentActions(connection: connection, transport: transport), transport)
  }

  @Test func getsOneTorrent() async throws {
    let json = """
      {"hash":"aaa","name":"Alpha","size":100,"progress":0.5,"state":"downloading",
       "downSpeed":1,"upSpeed":2,"ratio":0.5,"category":"","tags":[],
       "addedAt":"2026-11-01T10:00:00Z","savePath":"/d","seeds":1,"seedsTotal":2,
       "peers":3,"peersTotal":4,"downloaded":5,"uploaded":6,"seedTimeSeconds":7,"queuePosition":0}
      """
    let (actions, transport) = actions(["getTorrent": .json(json)])
    let torrent = try await actions.torrent(hash: "aaa")
    #expect(torrent.name == "Alpha")
    #expect(torrent.savePath == "/d")
    let sent = try #require(await transport.sent.first)
    #expect(sent.method == .get)
    #expect(sent.path == "/torrents/aaa")
  }

  @Test func getsThePeers() async throws {
    let (actions, transport) = actions(["getTorrentPeers": Sample.peers])
    let peers = try await actions.peers(of: "aaa")
    #expect(peers.map(\.address) == ["192.0.2.1:1", "192.0.2.2:2"])
    #expect(peers[0].client == "A 1.0")
    #expect(peers[1].client == nil)
    #expect(peers[1].incoming)
    let sent = try #require(await transport.sent.first)
    #expect(sent.method == .get)
    #expect(sent.path == "/torrents/aaa/peers")
  }

  @Test func getsTheFiles() async throws {
    let (actions, transport) = actions(["getTorrentFiles": Sample.files])
    let files = try await actions.files(of: "aaa")
    #expect(files.map(\.index) == [0, 1, 2])
    #expect(files[1].priority == .skip)
    #expect(files[2].priority == .high)
    #expect(files[0].done == 500)
    let sent = try #require(await transport.sent.first)
    #expect(sent.path == "/torrents/aaa/files")
  }

  @Test func aMagnetWithoutDetailsHasNoFiles() async throws {
    let (actions, _) = actions(["getTorrentFiles": Sample.noFiles])
    #expect(try await actions.files(of: "aaa").isEmpty)
  }

  @Test func failuresCarryUmbrasWords() async {
    let (actions, _) = actions([
      "getTorrent": Sample.gone, "getTorrentPeers": Sample.gone, "getTorrentFiles": Sample.gone,
    ])
    let expected = UmbraError(
      code: "torrent_not_found", message: "Umbra has no torrent with that hash.")
    await #expect(throws: expected) { _ = try await actions.torrent(hash: "x") }
    await #expect(throws: expected) { _ = try await actions.peers(of: "x") }
    await #expect(throws: expected) { _ = try await actions.files(of: "x") }
  }
}
