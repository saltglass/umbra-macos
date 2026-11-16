import Foundation
import HTTPTypes
import Testing

@testable import UmbraKit

/// Each action sends the right request, and Umbra's error message comes back as an `UmbraError`.
@Suite struct TorrentActionsTests {
  let connection = Connection(
    baseURL: URL(string: "http://127.0.0.1:7980")!, credential: .apiKey("key"))
  let hashes = ["aaa", "bbb"]

  func actions(_ replies: [String: RecordingTransport.Reply] = [:]) -> (
    TorrentActions, RecordingTransport
  ) {
    let transport = RecordingTransport(replies)
    return (TorrentActions(connection: connection, transport: transport), transport)
  }

  @Test(arguments: TorrentActions.Action.allCases)
  func eachPlainActionPostsItsName(_ action: TorrentActions.Action) async throws {
    let (actions, transport) = actions()
    try await actions.perform(action, on: hashes)
    let sent = try #require(await transport.sent.first)
    #expect(sent.operation == "torrentAction")
    #expect(sent.method == .post)
    #expect(sent.path == "/torrents/actions")
    #expect(sent.json == ["action": action.rawValue, "hashes": hashes])
  }

  @Test func theNamedShortcutsSendTheirAction() async throws {
    let (actions, transport) = actions()
    try await actions.pause(["a"])
    try await actions.resume(["a"])
    try await actions.forceStart(["a"])
    try await actions.recheck(["a"])
    try await actions.reannounce(["a"])
    let sent = await transport.sent.compactMap { $0.json?["action"] as? String }
    #expect(sent == ["pause", "resume", "forceStart", "recheck", "reannounce"])
  }

  @Test func nothingIsSentForNoTorrents() async throws {
    let (actions, transport) = actions()
    try await actions.pause([])
    try await actions.remove([], deleteFiles: true)
    try await actions.setCategory("x", for: [])
    try await actions.changeTags(add: ["x"], for: [])
    try await actions.changeTags(for: hashes)
    try await actions.addTrackers([], to: "aaa")
    try await actions.setFilePriorities([:], of: "aaa")
    #expect(await transport.sent.isEmpty)
  }

  @Test(arguments: [false, true])
  func removeSaysWhetherToDeleteFiles(_ deleteFiles: Bool) async throws {
    let (actions, transport) = actions()
    try await actions.remove(hashes, deleteFiles: deleteFiles)
    let sent = try #require(await transport.sent.first)
    #expect(sent.operation == "removeTorrents")
    #expect(sent.path == "/torrents/remove")
    #expect(sent.json == ["hashes": hashes, "deleteFiles": deleteFiles])
  }

  @Test func setCategoryPutsIt() async throws {
    let (actions, transport) = actions()
    try await actions.setCategory("films", for: hashes)
    try await actions.setCategory("", for: hashes)
    let sent = await transport.sent
    #expect(sent.map(\.operation) == ["setTorrentsCategory", "setTorrentsCategory"])
    #expect(sent[0].method == .put)
    #expect(sent[0].json == ["hashes": hashes, "category": "films"])
    #expect(sent[1].json == ["hashes": hashes, "category": ""])
  }

  @Test func changeTagsSendsOnlyWhatChanges() async throws {
    let (actions, transport) = actions()
    try await actions.changeTags(add: ["keep"], for: hashes)
    try await actions.changeTags(add: ["a"], remove: ["b"], for: hashes)
    let sent = await transport.sent
    #expect(sent[0].operation == "setTorrentsTags")
    #expect(sent[0].json == ["hashes": hashes, "add": ["keep"]])
    #expect(sent[1].json == ["hashes": hashes, "add": ["a"], "remove": ["b"]])
  }

  static let trackerList = """
    {"dht":true,"pex":true,"trackers":[
      {"url":"udp://b.example:1337","tier":1,"state":"working"},
      {"url":"http://a.example/announce","tier":0,"state":"working"},
      {"url":"udp://c.example:80","tier":1,"state":"error","message":"Unregistered torrent"}]}
    """

  @Test func addTrackersPostsThem() async throws {
    let (actions, transport) = actions()
    try await actions.addTrackers(["udp://new.example:80"], to: "aaa")
    let sent = try #require(await transport.sent.first)
    #expect(sent.operation == "addTorrentTrackers")
    #expect(sent.method == .post)
    #expect(sent.path == "/torrents/aaa/trackers")
    #expect(sent.json == ["urls": ["udp://new.example:80"]])
  }

  @Test func editTrackerKeepsItsTier() async throws {
    let (actions, transport) = actions(["getTorrentTrackers": .json(Self.trackerList)])
    try await actions.editTracker("udp://b.example:1337", to: "udp://b2.example:1337", of: "aaa")
    let sent = await transport.sent
    #expect(sent.map(\.operation) == ["getTorrentTrackers", "setTorrentTrackers"])
    #expect(sent[1].method == .put)
    #expect(
      sent[1].json == [
        "tiers": [["http://a.example/announce"], ["udp://b2.example:1337", "udp://c.example:80"]]
      ])
  }

  @Test func removeTrackersLeavesTheRest() async throws {
    let (actions, transport) = actions(["getTorrentTrackers": .json(Self.trackerList)])
    try await actions.removeTrackers(["udp://c.example:80"], of: "aaa")
    let sent = await transport.sent
    #expect(
      sent[1].json == [
        "tiers": [["http://a.example/announce"], ["udp://b.example:1337"]]
      ])
  }

  @Test func filePrioritiesGoInIndexOrder() async throws {
    let (actions, transport) = actions()
    try await actions.setFilePriorities([3: .skip, 0: .high], of: "aaa")
    let sent = try #require(await transport.sent.first)
    #expect(sent.operation == "setTorrentFilePriorities")
    #expect(sent.path == "/torrents/aaa/files")
    #expect(
      sent.json == [
        "files": [["index": 0, "priority": "high"], ["index": 3, "priority": "skip"]]
      ])
  }

  @Test func magnetLinkComesBack() async throws {
    let (actions, transport) = actions(["getTorrentMagnet": .json(#"{"magnet":"magnet:?xt=1"}"#)])
    #expect(try await actions.magnetLink(of: "aaa") == "magnet:?xt=1")
    #expect(await transport.sent.first?.path == "/torrents/aaa/magnet")
  }

  @Test func torrentFileComesBackAsBytes() async throws {
    let reply = RecordingTransport.Reply(
      status: .ok, contentType: "application/x-bittorrent", body: "d4:infoe")
    let (actions, transport) = actions(["exportTorrentFile": reply])
    #expect(try await actions.torrentFile(of: "aaa") == Data("d4:infoe".utf8))
    #expect(await transport.sent.first?.path == "/torrents/aaa/file")
  }

  static let speed = """
    {"downloadLimitKBs":500,"uploadLimitKBs":100,"slowMode":false,"slowDownloadKBs":50,
     "slowUploadKBs":10,"slowModeSchedule":{"enabled":true,"days":[1,2],"from":"08:00","to":"18:00"}}
    """

  @Test func slowModeChangesOnlyItself() async throws {
    let (actions, transport) = actions([
      "getSpeedSettings": .json(Self.speed),
      "putSpeedSettings": .json(Self.speed.replacingOccurrences(of: "false", with: "true")),
    ])
    let stored = try await actions.setSlowMode(true)
    #expect(stored.slowMode)
    let sent = await transport.sent
    #expect(sent.map(\.operation) == ["getSpeedSettings", "putSpeedSettings"])
    let put = try #require(sent[1].json)
    #expect(put["slowMode"] as? Bool == true)
    #expect(put["downloadLimitKBs"] as? Int == 500)
    #expect((put["slowModeSchedule"] as? NSDictionary)?["from"] as? String == "08:00")
  }

  // MARK: Errors

  @Test func anErrorAnswerSurfacesUmbrasMessage() async throws {
    let (actions, _) = actions([
      "torrentAction": .error(
        .notFound, code: "torrent_not_found", message: "Umbra has no torrent with that hash.")
    ])
    await #expect(
      throws: UmbraError(code: "torrent_not_found", message: "Umbra has no torrent with that hash.")
    ) {
      try await actions.pause(hashes)
    }
  }

  @Test func anEngineDownAnswerSurfacesItsMessage() async throws {
    let (actions, _) = actions([
      "setTorrentsCategory": .error(
        .serviceUnavailable, code: "engine_down", message: "The torrent engine isn't running.")
    ])
    do {
      try await actions.setCategory("films", for: hashes)
      Issue.record("didn't throw")
    } catch {
      #expect(error.message == "The torrent engine isn't running.")
      #expect(error.localizedDescription == "The torrent engine isn't running.")
    }
  }

  @Test func anErrorOnAReadSurfacesItsMessage() async throws {
    let (actions, transport) = actions([
      "getTorrentTrackers": .error(.notFound, code: "not_found", message: "Gone.")
    ])
    await #expect(throws: UmbraError(code: "not_found", message: "Gone.")) {
      try await actions.removeTrackers(["x"], of: "aaa")
    }
    #expect(await transport.sent.count == 1)  // nothing was put after the failed read
  }

  @Test func validationFieldsComeThrough() async throws {
    let body =
      #"{"code":"invalid","message":"Some fields are wrong.","fields":{"tiers.0":"Not a tracker address."}}"#
    let (actions, _) = actions([
      "setTorrentTrackers": .init(status: .unprocessableContent, body: body)
    ])
    do {
      try await actions.setTrackers([["nope"]], of: "aaa")
      Issue.record("didn't throw")
    } catch {
      #expect(error.fields == ["tiers.0": "Not a tracker address."])
    }
  }

  @Test func anUnexplainedErrorSaysSo() async throws {
    let (actions, _) = actions(["torrentAction": .init(status: .badGateway)])
    do {
      try await actions.pause(hashes)
      Issue.record("didn't throw")
    } catch {
      #expect(error.code == "http_502")
      #expect(error.message.contains("HTTP 502"))
    }
  }

  @Test func anUnreachableServerSaysSo() async throws {
    // Nothing listens on port 9 (the "discard" port) of this computer.
    let actions = TorrentActions(
      connection: Connection(baseURL: URL(string: "http://127.0.0.1:9")!, credential: .apiKey("k")))
    do {
      try await actions.pause(hashes)
      Issue.record("didn't throw")
    } catch {
      #expect(error.code == "unreachable")
      #expect(error.message.hasPrefix("Umbra couldn't be reached"))
    }
  }
}
