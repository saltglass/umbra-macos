import Foundation
import Testing
import UmbraAPI

@testable import UmbraKit

/// Reading the feed's JSON as Umbra really writes it.
@Suite struct FeedEventTests {
  // A torrent row as Go writes it, with a nanosecond time and one on a whole second.
  let torrentJSON = """
    {"hash":"aa","name":"Film","size":10,"progress":0.5,"state":"downloading","downSpeed":1,\
    "upSpeed":2,"ratio":0,"category":"","tags":["x"],"addedAt":"2026-11-12T10:00:00.123456789Z",\
    "completedAt":"2026-11-12T11:00:00Z","savePath":"/d","seeds":1,"seedsTotal":2,"peers":3,\
    "peersTotal":4,"downloaded":5,"uploaded":6,"seedTimeSeconds":7,"queuePosition":0,\
    "someFieldFromANewerUmbra":true}
    """

  @Test func readsASnapshotWithGoTimes() throws {
    let message = ServerSentEvent(
      type: "torrents.snapshot", data: #"{"rev":3,"torrents":[\#(torrentJSON)]}"#)
    guard case .snapshot(let snap) = try #require(try FeedEvent(message)) else {
      Issue.record("not a snapshot")
      return
    }
    #expect(snap.rev == 3)
    let added = try #require(snap.torrents.first?.addedAt)
    #expect(abs(added.timeIntervalSince1970 - 1_794_477_600.123) < 0.001)
    #expect(snap.torrents.first?.completedAt != nil)
  }

  @Test func readsADelta() throws {
    let message = ServerSentEvent(
      type: "torrents.delta",
      data: #"{"from":1,"rev":2,"changed":[\#(torrentJSON)],"removed":["bb"]}"#)
    #expect(
      try FeedEvent(message)
        == .delta(.init(from: 1, rev: 2, changed: [try decodeRow()], removed: ["bb"])))
  }

  func decodeRow() throws -> Components.Schemas.Torrent {
    try FeedJSON.decoder.decode(Components.Schemas.Torrent.self, from: Data(torrentJSON.utf8))
  }

  @Test func readsTransferWithTheVpnState() throws {
    let message = ServerSentEvent(
      type: "transfer",
      data: """
        {"downSpeed":1,"upSpeed":2,"downLimit":0,"upLimit":0,"slowMode":false,\
        "sessionDownloaded":0,"sessionUploaded":0,"freeSpace":0,"lowSpace":0,"incoming":true,\
        "dhtNodes":0,"vpn":"connected","vpnIp":"10.0.0.1"}
        """)
    guard case .transfer(let t) = try #require(try FeedEvent(message)) else {
      Issue.record("not transfer")
      return
    }
    #expect(t.vpn == .connected)
    #expect(t.vpnIp == "10.0.0.1")
  }

  @Test func readsCreationsFinishedAndSettings() throws {
    let creations = ServerSentEvent(
      type: "creations",
      data: """
        [{"id":"1","name":"n","path":"/p","state":"reading","files":1,"size":2,"read":1,\
        "pieceLength":16384,"pieces":1,"private":true,"seeding":false,\
        "started":"2026-11-12T10:00:00.5Z"}]
        """)
    guard case .creations(let list) = try #require(try FeedEvent(creations)) else {
      Issue.record("not creations")
      return
    }
    #expect(list.first?._private == true)

    let finished = ServerSentEvent(
      type: "torrent.finished", data: #"{"hash":"a","name":"A","size":9}"#)
    #expect(try FeedEvent(finished) == .finished(.init(hash: "a", name: "A", size: 9)))

    let settings = ServerSentEvent(type: "settings.changed", data: #"{"group":"security"}"#)
    #expect(try FeedEvent(settings) == .settingsChanged(group: "security"))
  }

  @Test func unknownKindIsSkippedNotAnError() throws {
    #expect(try FeedEvent(ServerSentEvent(type: "something.new", data: "{}")) == nil)
  }

  @Test func badJSONIsAnError() {
    #expect(throws: (any Error).self) {
      try FeedEvent(ServerSentEvent(type: "torrents.delta", data: "{not json"))
    }
  }
}
