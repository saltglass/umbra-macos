import Foundation
import Testing

@testable import UmbraKit

/// Made-up log lines and a fake Umbra for the Logs window's model.
private enum LogFixtures {
  static let token = "tok-7f3a9c"
  static let connection = Connection(
    baseURL: URL(string: "http://127.0.0.1:9")!, credential: .launchToken(token))

  /// One line the way Umbra writes it as JSON.
  static func entry(
    _ seq: Int, _ level: String = "info", _ message: String = "", source: String = "Umbra",
    attrs: [(String, String)] = []
  ) -> String {
    let message = message.isEmpty ? "line \(seq)" : message
    let details = attrs.map { #"{"key":"\#($0.0)","value":"\#($0.1)"}"# }.joined(separator: ",")
    let second = String(format: "%02d", seq % 60)
    return
      #"{"seq":\#(seq),"time":"2026-11-14T10:00:\#(second).250000000Z","level":"\#(level)","source":"\#(source)","message":"\#(message)","attrs":[\#(details)]}"#
  }

  /// A reply to GET /logs.
  static func page(_ entries: [String]) -> RecordingTransport.Reply {
    .json(
      #"{"entries":[\#(entries.joined(separator: ","))],"more":false,"counts":{"info":0,"warning":0,"error":0},"torrents":[]}"#
    )
  }

  /// A stream message.
  static func sse(_ entry: String) -> String { "event: log\ndata: \(entry)\n\n" }
}

@MainActor
private func makeModel(
  recent: [String], stream: [FakeByteSource.Script] = [.sendAndHold([])],
  sleeper: TestSleeper = TestSleeper(), file: String = "umbra log text\n"
) -> (LogsModel, ScriptedTransport, FakeByteSource) {
  let transport = ScriptedTransport([
    "getLogs": LogFixtures.page(recent),
    "downloadLogs": .init(
      status: .ok, contentType: "text/plain", body: file),
  ])
  let source = FakeByteSource(stream)
  let model = LogsModel(
    transport: transport, source: source, sleep: { try await sleeper.sleep($0) },
    timeZone: TimeZone(identifier: "UTC")!)
  return (model, transport, source)
}

@MainActor
@Suite struct LogsModelTests {
  @Test func nothingHappensWhenNotConnected() async {
    let (model, transport, source) = makeModel(recent: [])
    model.open(connection: nil)
    #expect(model.phase == .notConnected)
    try? await Task.sleep(for: .milliseconds(30))
    #expect(await transport.sent.isEmpty)
    #expect(source.requests.isEmpty)
    #expect(model.lines.isEmpty)
    #expect(model.emptyMessage == nil)
  }

  @Test func loadsRecentLinesThenFollowsTheStreamWithoutDoubles() async {
    // Lines 2 and 3 arrive in the first load and again on the stream.
    let (model, transport, source) = makeModel(
      recent: [LogFixtures.entry(1), LogFixtures.entry(2), LogFixtures.entry(3)],
      stream: [
        .sendAndHold([
          LogFixtures.sse(LogFixtures.entry(2)), LogFixtures.sse(LogFixtures.entry(3)),
          LogFixtures.sse(LogFixtures.entry(4)), LogFixtures.sse(LogFixtures.entry(5)),
        ])
      ])
    model.open(connection: LogFixtures.connection)
    #expect(await eventually { model.lines.count == 5 })
    #expect(model.lines.map(\.id) == [1, 2, 3, 4, 5])
    #expect(model.phase == .live)
    #expect(model.statusText == "5 lines")
    // The stream asked only for lines after the newest one loaded.
    #expect(source.requests.first?.url?.query == "after=3")
    let first = await transport.sent.first
    #expect(first?.operation == "getLogs")
    #expect(first?.path.contains("limit=5000") == true)
    model.close()
  }

  @Test func theStreamIsClosedWhenTheWindowCloses() async {
    let (model, _, source) = makeModel(recent: [LogFixtures.entry(1)])
    model.open(connection: LogFixtures.connection)
    #expect(await eventually { model.phase == .live })
    model.close()
    #expect(await eventually { source.stopped == 1 })
    #expect(model.phase == .notConnected)
  }

  @Test func keepsOnlyTheNewestFiveThousand() async {
    let recent = (1...5000).map { LogFixtures.entry($0) }
    let more = (5001...5010).map { LogFixtures.sse(LogFixtures.entry($0)) }
    let (model, _, _) = makeModel(recent: recent, stream: [.sendAndHold(more)])
    model.open(connection: LogFixtures.connection)
    #expect(await eventually { model.lines.last?.id == 5010 })
    #expect(model.lines.count == LogsModel.capacity)
    #expect(model.lines.first?.id == 11)
    model.close()
  }

  @Test func levelAndSearchFilterAndSayHowManyAreShown() async {
    let (model, _, _) = makeModel(recent: [
      LogFixtures.entry(1, "info", "Started"),
      LogFixtures.entry(2, "warning", "Tracker slow", source: "Some Torrent"),
      LogFixtures.entry(3, "error", "Disk full"),
      LogFixtures.entry(4, "info", "Listening on port 6881"),
    ])
    model.open(connection: LogFixtures.connection)
    #expect(await eventually { model.lines.count == 4 })
    #expect(model.statusText == "4 lines")

    model.levelFilter = .warningsAndErrors
    #expect(model.visibleLines.map(\.id) == [2, 3])
    #expect(model.statusText == "2 of 4 shown")

    model.levelFilter = .errors
    #expect(model.visibleLines.map(\.id) == [3])

    model.levelFilter = .all
    model.searchText = " PORT "
    #expect(model.visibleLines.map(\.id) == [4])
    #expect(model.statusText == "1 of 4 shown")

    // The search looks at the source too.
    model.searchText = "some torrent"
    #expect(model.visibleLines.map(\.id) == [2])

    model.searchText = "nothing like this"
    #expect(model.visibleLines.isEmpty)
    #expect(model.emptyMessage == "No lines match.")

    model.searchText = ""
    #expect(model.statusText == "4 lines")
    model.close()
  }

  @Test func newStreamLinesAreFilteredToo() async {
    let (model, _, _) = makeModel(
      recent: [LogFixtures.entry(1)],
      stream: [
        .sendAndHold([
          LogFixtures.sse(LogFixtures.entry(2, "warning")),
          LogFixtures.sse(LogFixtures.entry(3, "info")),
        ])
      ])
    model.levelFilter = .warningsAndErrors
    model.open(connection: LogFixtures.connection)
    #expect(await eventually { model.lines.count == 3 })
    #expect(model.visibleLines.map(\.id) == [2])
    model.close()
  }

  @Test func followingPausesWhenScrolledUpAndResumesAtTheEnd() {
    let model = LogsModel()
    #expect(model.isFollowing)  // on by default
    model.personScrolled(atEnd: false)
    #expect(!model.isFollowing)
    model.personScrolled(atEnd: false)
    #expect(!model.isFollowing)
    model.personScrolled(atEnd: true)
    #expect(model.isFollowing)
    // The toolbar toggle can turn it on or off too.
    model.isFollowing = false
    #expect(!model.isFollowing)
  }

  @Test func newLinesDoNotChangeWhetherItIsFollowing() async {
    let (model, _, _) = makeModel(
      recent: [LogFixtures.entry(1)],
      stream: [.sendAndHold([LogFixtures.sse(LogFixtures.entry(2))])])
    model.isFollowing = false
    model.open(connection: LogFixtures.connection)
    #expect(await eventually { model.lines.count == 2 })
    #expect(!model.isFollowing)
    model.close()
  }

  @Test func clearEmptiesTheViewAndLinesDoNotComeBack() async {
    let sleeper = TestSleeper()
    let (model, _, source) = makeModel(
      recent: [LogFixtures.entry(1), LogFixtures.entry(2)],
      stream: [
        .send([LogFixtures.sse(LogFixtures.entry(3))]),
        .sendAndHold([LogFixtures.sse(LogFixtures.entry(3)), LogFixtures.sse(LogFixtures.entry(4))]
        ),
      ], sleeper: sleeper)
    model.open(connection: LogFixtures.connection)
    #expect(await eventually { model.phase == .reconnecting })
    #expect(model.lines.map(\.id) == [1, 2, 3])
    model.clear()
    #expect(model.lines.isEmpty)
    #expect(model.statusText == "0 lines")
    await sleeper.allow()
    #expect(await eventually { model.lines.count == 1 })
    // Line 3 was seen before, so only line 4 is new.
    #expect(model.lines.map(\.id) == [4])
    #expect(source.requests.last?.url?.query == "after=3")
    model.close()
  }

  @Test func streamDropsThenReconnectsQuietlyWithoutGapsOrDoubles() async {
    let sleeper = TestSleeper()
    let (model, _, source) = makeModel(
      recent: [LogFixtures.entry(1)],
      stream: [
        .send([LogFixtures.sse(LogFixtures.entry(2))]),
        .sendAndHold([LogFixtures.sse(LogFixtures.entry(3)), LogFixtures.sse(LogFixtures.entry(4))]
        ),
      ], sleeper: sleeper)
    model.open(connection: LogFixtures.connection)
    #expect(await eventually { model.phase == .reconnecting })
    #expect(model.statusNote == "Reconnecting…")
    #expect(await sleeper.durations == [.seconds(1)])
    #expect(model.lines.map(\.id) == [1, 2])

    await sleeper.allow()
    #expect(await eventually { model.lines.count == 4 })
    #expect(model.lines.map(\.id) == [1, 2, 3, 4])
    #expect(model.phase == .live)
    #expect(model.statusNote == nil)
    #expect(source.requests.map { $0.url?.query } == ["after=1", "after=2"])
    model.close()
  }

  @Test func aFailedFirstLoadIsRetried() async {
    let sleeper = TestSleeper()
    let (model, transport, _) = makeModel(recent: [LogFixtures.entry(1)], sleeper: sleeper)
    await transport.set(
      "getLogs", .error(.serviceUnavailable, code: "engine_down", message: "Engine down."))
    model.open(connection: LogFixtures.connection)
    #expect(await eventually { model.phase == .reconnecting })
    await transport.set("getLogs", LogFixtures.page([LogFixtures.entry(1)]))
    await sleeper.allow()
    #expect(await eventually { model.lines.count == 1 })
    #expect(model.phase == .live)
    model.close()
  }

  @Test func aRefusedCredentialStopsTheStream() async {
    let (model, _, source) = makeModel(
      recent: [LogFixtures.entry(1)], stream: [.status(401)])
    model.open(connection: LogFixtures.connection)
    #expect(await eventually { model.phase == .notConnected && !source.requests.isEmpty })
    #expect(source.requests.count == 1)
  }

  // MARK: Hiding the credential

  @Test func theCredentialIsReplacedInShownAndCopiedText() async {
    let token = LogFixtures.token
    let (model, _, _) = makeModel(
      recent: [
        LogFixtures.entry(1, "info", "login with \(token) ok"),
        LogFixtures.entry(2, "warning", "plain", attrs: [("header", "X-Token: \(token)")]),
      ],
      stream: [.sendAndHold([LogFixtures.sse(LogFixtures.entry(3, "error", "again \(token)"))])])
    model.open(connection: LogFixtures.connection)
    #expect(await eventually { model.lines.count == 3 })
    for line in model.lines {
      #expect(!line.text.contains(token))
      #expect(!line.plainText().contains(token))
    }
    #expect(model.lines[0].text == "login with ••• ok")
    #expect(model.lines[1].text == "plain  header=X-Token: •••")
    // Searching for the credential finds nothing, since it is never held.
    model.searchText = token
    #expect(model.visibleLines.isEmpty)
    #expect(!model.copyText(for: [1, 2, 3]).contains(token))
    model.close()
  }

  @Test func copiedTextIsOneLinePerSelectedLineInListOrder() async {
    let (model, _, _) = makeModel(recent: [
      LogFixtures.entry(1, "info", "first"),
      LogFixtures.entry(2, "warning", "second", source: "A Torrent"),
      LogFixtures.entry(3, "error", "third"),
    ])
    model.open(connection: LogFixtures.connection)
    #expect(await eventually { model.lines.count == 3 })
    #expect(
      model.copyText(for: [3, 2])
        == "2026-11-14 10:00:02  Warning  A Torrent  second\n"
        + "2026-11-14 10:00:03  Error  Umbra  third")
    model.close()
  }

  // MARK: Saving

  @Test func theSaveRequestCarriesTheFiltersAndHidesTheCredential() async throws {
    let file = "10:00 info started\n10:01 error token \(LogFixtures.token)\n"
    let (model, transport, _) = makeModel(recent: [LogFixtures.entry(1)], file: file)
    model.open(connection: LogFixtures.connection)
    #expect(await eventually { model.phase == .live })
    model.levelFilter = .warningsAndErrors
    model.searchText = "disk"
    let data = try await model.downloadLogs()
    let sent = await transport.sent.last
    #expect(sent?.operation == "downloadLogs")
    #expect(sent?.method == .get)
    #expect(sent?.path.contains("levels=warning%2Cerror") == true)
    #expect(sent?.path.contains("q=disk") == true)
    #expect(String(decoding: data, as: UTF8.self) == "10:00 info started\n10:01 error token •••\n")

    model.levelFilter = .all
    model.searchText = ""
    _ = try await model.downloadLogs()
    let plain = await transport.sent.last
    #expect(plain?.path.contains("levels") == false)
    #expect(plain?.path.contains("q=") == false)
    model.close()
  }

  @Test func savingWhenNotConnectedFails() async {
    let model = LogsModel()
    await #expect(throws: UmbraError.self) { try await model.downloadLogs() }
  }

  @Test func theSuggestedFileNameHasTheDate() {
    let model = LogsModel(timeZone: TimeZone(identifier: "UTC")!)
    let day = Date(timeIntervalSince1970: 1_794_493_800)  // 12 November 2026
    #expect(model.suggestedFileName(now: day) == "umbra-logs-2026-11-12.txt")
  }

  @Test func statusTextForOneLineAndNone() async {
    let (model, _, _) = makeModel(recent: [LogFixtures.entry(1)])
    #expect(model.statusText == "0 lines")
    model.open(connection: LogFixtures.connection)
    #expect(await eventually { model.lines.count == 1 })
    #expect(model.statusText == "1 line")
    model.close()
  }
}
