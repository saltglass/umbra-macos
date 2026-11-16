import Foundation
import HTTPTypes
import Testing
import UmbraAPI

@testable import UmbraKit

/// Each settings group is read and replaced with the right request, Umbra's
/// answer comes back decoded, and a refusal carries Umbra's own words.
@Suite struct SettingsActionsTests {
  let connection = Connection(
    baseURL: URL(string: "http://127.0.0.1:7980")!, credential: .apiKey("key"))

  func actions(_ replies: [String: RecordingTransport.Reply]) -> (
    SettingsActions, RecordingTransport
  ) {
    let transport = RecordingTransport(replies)
    return (SettingsActions(connection: connection, transport: transport), transport)
  }

  static let queueJSON = #"{"maxActiveDownloads":3,"maxActiveSeeds":25}"#
  static let seedingJSON = #"{"ratio":1.5,"seedingMinutes":null,"inactiveMinutes":30}"#
  static let speedJSON = """
    {"downloadLimitKBs":0,"uploadLimitKBs":500,"slowMode":false,"slowDownloadKBs":100,\
    "slowUploadKBs":50,"slowModeSchedule":{"enabled":true,"days":[1,2],"from":"08:00","to":"17:00"}}
    """
  static let connectionJSON = #"{"listenPort":6881,"dht":true,"pex":false}"#
  static let downloadsJSON = """
    {"folder":"/d","defaultFolder":"/data/downloads","incompleteFolder":"",\
    "categories":[{"name":"films","folder":""}],"lowSpaceWarningGB":5,"watchFolder":""}
    """
  static let notificationsJSON = """
    {"enabled":true,"host":"smtp.example.com","port":587,"security":"starttls","username":"me",\
    "passwordSet":true,"from":"a@example.com","to":"b@example.com","onFinished":true,\
    "onError":false,"onVpn":true,"onLowDisk":false}
    """

  @Test func queueRoundTrips() async throws {
    let (actions, transport) = actions([
      "getQueueSettings": .json(Self.queueJSON), "putQueueSettings": .json(Self.queueJSON),
    ])
    var queue = try await actions.queue()
    #expect(queue.maxActiveDownloads == 3 && queue.maxActiveSeeds == 25)
    queue.maxActiveSeeds = 0
    _ = try await actions.setQueue(queue)
    let sent = await transport.sent
    #expect(sent.map(\.operation) == ["getQueueSettings", "putQueueSettings"])
    #expect(sent[1].method == .put)
    #expect(sent[1].path == "/settings/queue")
    #expect(sent[1].json == ["maxActiveDownloads": 3, "maxActiveSeeds": 0])
  }

  @Test func seedingRoundTripsAndSendsNoGoalAsMissing() async throws {
    let (actions, transport) = actions([
      "getSeedingSettings": .json(Self.seedingJSON), "putSeedingSettings": .json(Self.seedingJSON),
    ])
    var seeding = try await actions.seeding()
    #expect(seeding.ratio == 1.5 && seeding.seedingMinutes == nil && seeding.inactiveMinutes == 30)
    seeding.ratio = nil
    let stored = try await actions.setSeeding(seeding)
    #expect(stored.ratio == 1.5)  // what Umbra answered, not what was sent
    let sent = try #require(await transport.sent.last)
    #expect(sent.path == "/settings/seeding")
    // A goal of none is left out, which Umbra reads as none.
    #expect(sent.json == ["inactiveMinutes": 30])
  }

  @Test func speedRoundTrips() async throws {
    let (actions, transport) = actions([
      "getSpeedSettings": .json(Self.speedJSON), "putSpeedSettings": .json(Self.speedJSON),
    ])
    let speed = try await actions.speed()
    #expect(speed.uploadLimitKBs == 500 && speed.slowModeSchedule.days == [1, 2])
    _ = try await actions.setSpeed(speed)
    let sent = try #require(await transport.sent.last)
    #expect(sent.operation == "putSpeedSettings" && sent.path == "/settings/speed")
    #expect(sent.json?["uploadLimitKBs"] as? Int == 500)
  }

  @Test func connectionRoundTrips() async throws {
    let (actions, transport) = actions([
      "getConnectionSettings": .json(Self.connectionJSON),
      "putConnectionSettings": .json(Self.connectionJSON),
    ])
    var settings = try await actions.connection()
    #expect(settings.listenPort == 6881 && settings.dht && !settings.pex)
    settings.pex = true
    _ = try await actions.setConnection(settings)
    let sent = try #require(await transport.sent.last)
    #expect(sent.path == "/settings/connection")
    #expect(sent.json == ["listenPort": 6881, "dht": true, "pex": true])
  }

  @Test func downloadsRoundTrips() async throws {
    let (actions, transport) = actions([
      "getDownloadsSettings": .json(Self.downloadsJSON),
      "putDownloadsSettings": .json(Self.downloadsJSON),
    ])
    let downloads = try await actions.downloads()
    #expect(downloads.folder == "/d" && downloads.categories.map(\.name) == ["films"])
    _ = try await actions.setDownloads(downloads)
    let sent = try #require(await transport.sent.last)
    #expect(sent.operation == "putDownloadsSettings" && sent.path == "/settings/downloads")
    #expect(sent.json?["folder"] as? String == "/d")
  }

  @Test func notificationsRoundTripAndThePasswordIsOnlyEverAChange() async throws {
    let (actions, transport) = actions([
      "getNotificationsSettings": .json(Self.notificationsJSON),
      "putNotificationsSettings": .json(Self.notificationsJSON),
    ])
    let group = SettingsGroup<NotificationsDraft>.notifications
    var draft = try await group.read(actions)
    #expect(draft.settings.passwordSet && draft.password == .unchanged)

    // Unchanged: no password at all in the request.
    _ = try await group.write(draft, actions)
    // Replaced: the new one. Removed: "".
    draft.password = .replaced("hunter2")
    let saved = try await group.write(draft, actions)
    draft.password = .removed
    _ = try await group.write(draft, actions)

    let puts = await transport.sent.filter { $0.operation == "putNotificationsSettings" }
    #expect(puts.count == 3)
    #expect(puts[0].json?["password"] == nil)
    #expect(puts[1].json?["password"] as? String == "hunter2")
    #expect(puts[2].json?["password"] as? String == "")
    #expect(puts[0].json?["passwordSet"] == nil)  // read-only; never sent
    #expect(puts[0].json?["host"] as? String == "smtp.example.com")
    // What comes back holds no password, only "unchanged".
    #expect(saved.password == .unchanged)
  }

  @Test func aSecretNeverShowsInText() {
    let change = SecretChange.replaced("hunter2")
    var dumped = ""
    dump(change, to: &dumped)
    for text in [String(describing: change), String(reflecting: change), "\(change)", dumped] {
      #expect(!text.contains("hunter2"))
    }
    var draftDump = ""
    dump(
      NotificationsDraft(
        .init(
          enabled: true, host: "h", port: 1, security: .tls, username: "u", passwordSet: true,
          from: "f", to: "t", onFinished: true, onError: true, onVpn: true, onLowDisk: true),
        password: change), to: &draftDump)
    #expect(!draftDump.contains("hunter2"))
  }

  @Test func aRefusalCarriesUmbrasWordsAndFields() async throws {
    let refusal = RecordingTransport.Reply.json(
      #"{"code":"invalid","message":"Some fields need attention.","fields":{"maxActiveDownloads":"Enter a number from 1 to 50."}}"#,
      status: .unprocessableContent)
    let (actions, _) = actions(["putQueueSettings": refusal])
    let error = await #expect(throws: UmbraError.self) {
      _ = try await actions.setQueue(.init(maxActiveDownloads: 0, maxActiveSeeds: 1))
    }
    #expect(error?.message == "Some fields need attention.")
    #expect(error?.fields == ["maxActiveDownloads": "Enter a number from 1 to 50."])
  }

  @Test func aFailedReadSaysWhy() async {
    let (actions, _) = actions([
      "getSeedingSettings": .error(.unauthorized, code: "unauthorized", message: "Sign in first.")
    ])
    let error = await #expect(throws: UmbraError.self) { _ = try await actions.seeding() }
    #expect(error?.message == "Sign in first.")
  }
}
