import Foundation
import Testing
import UmbraAPI

@testable import UmbraKit

/// When the inspector asks Umbra for things, how often, and what it keeps.
@MainActor
@Suite("the inspector model") struct InspectorModelTests {
  let connection = Connection(
    baseURL: URL(string: "http://127.0.0.1:7980")!, credential: .apiKey("key"))

  /// A window model with Alpha..Delta (hashes a1..d4), the inspector open
  /// on `a1`, and an inspector model talking to `transport`.
  func setUp(
    _ replies: [String: RecordingTransport.Reply] = [:], connected: Bool = true,
    sleeper: TestSleeper = TestSleeper()
  ) -> (InspectorModel, MainWindowModel, ScriptedTransport) {
    let (window, _) = makeModel(defaults: throwawayDefaults())
    window.inspectorShown = true
    window.selection = ["a1"]
    let transport = ScriptedTransport(replies)
    let actions = TorrentActions(connection: connection, transport: transport)
    let inspector = InspectorModel(
      window: window, actions: { connected ? actions : nil }, now: { testNow },
      sleep: { try await sleeper.sleep($0) })
    return (inspector, window, transport)
  }

  // MARK: What is shown

  @Test func subjectFollowsTheSelection() {
    let (inspector, window, _) = setUp()
    window.selection = []
    #expect(inspector.subject == .none)
    window.selection = ["a1"]
    if case .one(let row) = inspector.subject {
      #expect(row.name == "Alpha")
    } else {
      Issue.record("expected one torrent")
    }
    window.selection = ["a1", "c3"]
    if case .several(let summary) = inspector.subject {
      #expect(summary.title == "2 torrents selected")
      #expect(summary.detail.hasPrefix("400 B total"))
    } else {
      Issue.record("expected several torrents")
    }
  }

  // MARK: When it asks

  @Test func watchesOnlyWhenTheTabIsOneThatFetchesTheInspectorIsOpenAndOneIsSelected() {
    let (inspector, window, _) = setUp()
    // General fetches nothing.
    inspector.tab = .general
    #expect(inspector.watch == nil)
    inspector.tab = .trackers
    #expect(inspector.watch == InspectorModel.Watch(hash: "a1", tab: .trackers))
    inspector.tab = .peers
    #expect(inspector.watch == InspectorModel.Watch(hash: "a1", tab: .peers))
    inspector.tab = .files
    #expect(inspector.watch == InspectorModel.Watch(hash: "a1", tab: .files))

    window.selection = ["b2"]
    #expect(inspector.watch?.hash == "b2")
    window.selection = ["a1", "b2"]
    #expect(inspector.watch == nil)
    window.selection = []
    #expect(inspector.watch == nil)
    window.selection = ["a1"]
    window.inspectorShown = false
    #expect(inspector.watch == nil)
    window.inspectorShown = true
    #expect(inspector.watch != nil)
  }

  @Test func doesNotWatchWhileNotConnected() {
    let (inspector, _, _) = setUp(connected: false)
    inspector.tab = .peers
    #expect(inspector.watch == nil)
    #expect(!inspector.connected)
  }

  @Test func eachTabAsksOnTheWebPagesSchedule() {
    #expect(InspectorModel.Tab.trackers.refreshInterval == .seconds(5))
    #expect(InspectorModel.Tab.peers.refreshInterval == .seconds(2))
    #expect(InspectorModel.Tab.files.refreshInterval == .seconds(3))
    #expect(InspectorModel.Tab.general.refreshInterval == nil)
  }

  @Test(
    "fetches at once, waits its tab's interval, then fetches again",
    arguments: [
      (InspectorModel.Tab.trackers, "getTorrentTrackers", "/torrents/a1/trackers", 5),
      (.peers, "getTorrentPeers", "/torrents/a1/peers", 2),
      (.files, "getTorrentFiles", "/torrents/a1/files", 3),
    ])
  func runLoop(tab: InspectorModel.Tab, operation: String, path: String, seconds: Int)
    async throws
  {
    let sleeper = TestSleeper()
    let (inspector, _, transport) = setUp(
      [
        "getTorrentTrackers": Sample.trackers, "getTorrentPeers": Sample.peers,
        "getTorrentFiles": Sample.files,
      ], sleeper: sleeper)
    inspector.tab = tab
    let task = Task { await inspector.run(.init(hash: "a1", tab: tab)) }
    #expect(await eventually { await sleeper.durations.count == 1 })
    #expect(await transport.count(operation) == 1)
    #expect(await sleeper.durations == [.seconds(seconds)])
    #expect(await transport.sent.first?.path == path)

    await sleeper.allow()
    #expect(await eventually { await transport.count(operation) == 2 })
    task.cancel()
    await task.value
  }

  @Test func cancellingStopsTheFetching() async {
    let sleeper = TestSleeper()
    let (inspector, _, transport) = setUp(["getTorrentPeers": Sample.peers], sleeper: sleeper)
    inspector.tab = .peers
    let task = Task { await inspector.run(.init(hash: "a1", tab: .peers)) }
    #expect(await eventually { await transport.count("getTorrentPeers") == 1 })
    task.cancel()
    await task.value
    await sleeper.allow(5)
    try? await Task.sleep(for: .milliseconds(30))
    #expect(await transport.count("getTorrentPeers") == 1)
  }

  @Test func generalFetchesNothing() async {
    let (inspector, _, transport) = setUp()
    await inspector.run(.init(hash: "a1", tab: .general))
    #expect(await transport.sent.isEmpty)
  }

  // MARK: What it keeps

  @Test func keepsTheTrackersAndPeersItFetched() async {
    let (inspector, _, _) = setUp([
      "getTorrentTrackers": Sample.trackers, "getTorrentPeers": Sample.peers,
    ])
    #expect(inspector.trackers.isLoading)
    await inspector.refresh(.init(hash: "a1", tab: .trackers))
    let trackers = inspector.trackers.value
    #expect(trackers?.rows.map(\.url) == ["udp://t.example/a", "https://t.example/b"])
    #expect(trackers?.rows[1].message == "Unregistered torrent")
    #expect(trackers?.findsPeersElsewhere == true)

    await inspector.refresh(.init(hash: "a1", tab: .peers))
    // Busiest first.
    #expect(inspector.peers.value?.map(\.address) == ["192.0.2.2:2", "192.0.2.1:1"])
  }

  @Test func whatArrivedForAnotherTorrentIsNeverShown() async {
    let (inspector, window, _) = setUp(["getTorrentTrackers": Sample.trackers])
    await inspector.refresh(.init(hash: "a1", tab: .trackers))
    #expect(inspector.trackers.value != nil)
    // Another torrent: nothing of the first one's.
    window.selection = ["b2"]
    #expect(inspector.trackers.isLoading)
    #expect(inspector.trackers.value == nil)
    // An answer that was still on its way for the first one is thrown away.
    await inspector.refresh(.init(hash: "a1", tab: .trackers))
    #expect(inspector.trackers.isLoading)
    // Back on the first: its trackers are there again.
    window.selection = ["a1"]
    #expect(inspector.trackers.value != nil)
  }

  @Test func aFailedFetchShowsUmbrasWordsAndKeepsWhatWasThere() async {
    let (inspector, _, transport) = setUp(["getTorrentPeers": Sample.gone])
    await inspector.refresh(.init(hash: "a1", tab: .peers))
    #expect(inspector.peers.failure == "Umbra has no torrent with that hash.")
    #expect(inspector.peers.value == nil)
    #expect(!inspector.peers.isLoading)

    await transport.set("getTorrentPeers", Sample.peers)
    await inspector.refresh(.init(hash: "a1", tab: .peers))
    #expect(inspector.peers.failure == nil)
    #expect(inspector.peers.value?.count == 2)

    await transport.set(
      "getTorrentPeers",
      .error(.serviceUnavailable, code: "engine_down", message: "Umbra's engine is restarting."))
    await inspector.refresh(.init(hash: "a1", tab: .peers))
    #expect(inspector.peers.failure == "Umbra's engine is restarting.")
    #expect(inspector.peers.value?.count == 2)
    // A failed fetch isn't an alert.
    #expect(inspector.changeFailure == nil)
    #expect(inspector.peers.value != nil)
  }

  @Test func aMagnetWithoutDetailsHasAnEmptyTree() async {
    let (inspector, _, _) = setUp(["getTorrentFiles": Sample.noFiles])
    await inspector.refresh(.init(hash: "a1", tab: .files))
    #expect(inspector.files.value?.tree.isEmpty == true)
    #expect(inspector.files.value?.rows.isEmpty == true)
    #expect(!inspector.files.isLoading)
  }

  @Test func theTreeIsNotRemadeWhenNothingChanged() async {
    let (inspector, _, _) = setUp(["getTorrentFiles": Sample.files])
    await inspector.refresh(.init(hash: "a1", tab: .files))
    let first = inspector.files
    await inspector.refresh(.init(hash: "a1", tab: .files))
    #expect(inspector.files == first)
    #expect(
      first.value?.rows.map(\.id) == [
        "Show", "Show/sub", "Show/sub/c.srt", "Show/a.mkv", "Show/b.mkv",
      ])
  }

  @Test func closingAFolderHidesItsFilesAndIsRememberedAcrossFetches() async {
    let (inspector, window, _) = setUp(["getTorrentFiles": Sample.files])
    await inspector.refresh(.init(hash: "a1", tab: .files))
    inspector.toggleFolder("Show/sub")
    #expect(
      inspector.files.value?.rows.map(\.id) == ["Show", "Show/sub", "Show/a.mkv", "Show/b.mkv"])
    await inspector.refresh(.init(hash: "a1", tab: .files))
    #expect(inspector.files.value?.rows.count == 4)
    inspector.toggleFolder("Show/sub")
    #expect(inspector.files.value?.rows.count == 5)
    // Another torrent starts with everything open.
    inspector.toggleFolder("Show/sub")
    window.selection = ["b2"]
    #expect(inspector.files.value == nil)
  }

  // MARK: Changing files

  @Test func tickingAFolderSendsTheFilesUnderItAndShowsItAtOnce() async throws {
    let (inspector, _, transport) = setUp(["getTorrentFiles": Sample.files])
    await inspector.refresh(.init(hash: "a1", tab: .files))
    let top = try #require(inspector.files.value?.rows.first)
    #expect(top.tick == .mixed)
    await inspector.click(top)
    let put = try #require(
      await transport.sent.first { $0.operation == "setTorrentFilePriorities" })
    #expect(put.path == "/torrents/a1/files")
    #expect(put.method == .put)
    // Only the skipped file changes; the High one stays High.
    let files = put.json?["files"] as? [[String: Any]]
    #expect(files?.count == 1)
    #expect(files?.first?["index"] as? Int == 1)
    #expect(files?.first?["priority"] as? String == "normal")
    // And the files are fetched again afterwards.
    #expect(await transport.count("getTorrentFiles") == 2)
    #expect(inspector.changeFailure == nil)
  }

  @Test func aFailedFileChangeIsReportedInlineAndTheTruthIsFetchedBack() async throws {
    let (inspector, _, transport) = setUp(["getTorrentFiles": Sample.files])
    await inspector.refresh(.init(hash: "a1", tab: .files))
    await transport.set(
      "setTorrentFilePriorities",
      .error(.conflict, code: "conflict", message: "Umbra can't change that file now."))
    let top = try #require(inspector.files.value?.rows.first)
    await inspector.click(top)
    #expect(inspector.changeFailure == "Umbra can't change that file now.")
    // Back to what Umbra says: file 1 is still skipped.
    #expect(inspector.files.value?.rows.first?.tick == .mixed)
    inspector.dismissChangeFailure()
    #expect(inspector.changeFailure == nil)
  }

  @Test func choosingAPriorityForAFolderSendsOnlyTheFilesThatDiffer() async throws {
    let (inspector, _, transport) = setUp(["getTorrentFiles": Sample.files])
    await inspector.refresh(.init(hash: "a1", tab: .files))
    let top = try #require(inspector.files.value?.rows.first)
    await inspector.choose(.high, for: top)
    let put = try #require(
      await transport.sent.first { $0.operation == "setTorrentFilePriorities" })
    let files = (put.json?["files"] as? [[String: Any]]) ?? []
    #expect(files.compactMap { $0["index"] as? Int }.sorted() == [0, 1])
  }

  @Test func nothingToChangeSendsNothing() async throws {
    let (inspector, _, transport) = setUp(["getTorrentFiles": Sample.files])
    await inspector.refresh(.init(hash: "a1", tab: .files))
    let high = try #require(inspector.files.value?.rows.first { $0.id == "Show/sub/c.srt" })
    await inspector.choose(.high, for: high)
    #expect(await transport.count("setTorrentFilePriorities") == 0)
  }

  // MARK: Changing trackers

  @Test func addressesAreOnePerLineTrimmedWithBlanksDropped() {
    #expect(
      InspectorModel.addresses(in: "  udp://a/x \n\n https://b/y\r\n   \n") == [
        "udp://a/x", "https://b/y",
      ])
    #expect(InspectorModel.addresses(in: " \n ").isEmpty)
  }

  @Test func addingTrackersSendsThemAndFetchesTheListAgain() async {
    let (inspector, _, transport) = setUp(["getTorrentTrackers": Sample.trackers])
    let failure = await inspector.addTrackers("udp://x/1\nudp://x/2")
    #expect(failure == nil)
    let post = await transport.sent.first { $0.operation == "addTorrentTrackers" }
    #expect(post?.path == "/torrents/a1/trackers")
    #expect((post?.json?["urls"] as? [String]) == ["udp://x/1", "udp://x/2"])
    #expect(await transport.count("getTorrentTrackers") == 1)
    #expect(inspector.trackers.value?.rows.count == 2)
  }

  @Test func addingNothingSaysSoWithoutAskingUmbra() async {
    let (inspector, _, transport) = setUp()
    #expect(await inspector.addTrackers("  \n") == "Enter a tracker address.")
    #expect(await inspector.editTracker("udp://x", to: "") == "Enter a tracker address.")
    #expect(await transport.sent.isEmpty)
  }

  @Test func aRefusedAddComesBackForTheBoxToShow() async {
    let (inspector, _, _) = setUp([
      "addTorrentTrackers": .error(
        .unprocessableContent, code: "invalid", message: "That isn't a tracker address.")
    ])
    #expect(await inspector.addTrackers("nonsense") == "That isn't a tracker address.")
    // Shown in the box, not as the inspector's line.
    #expect(inspector.changeFailure == nil)
  }

  @Test func editingReadsTheListThenWritesItWithTheNewAddress() async {
    let (inspector, _, transport) = setUp(["getTorrentTrackers": Sample.trackers])
    let failure = await inspector.editTracker("https://t.example/b", to: "https://t.example/c")
    #expect(failure == nil)
    let put = await transport.sent.first { $0.operation == "setTorrentTrackers" }
    #expect(
      (put?.json?["tiers"] as? [[String]]) == [["udp://t.example/a"], ["https://t.example/c"]])
  }

  @Test func removingTrackersFailureShowsInTheInspector() async {
    let (inspector, _, _) = setUp([
      "getTorrentTrackers": Sample.trackers,
      "setTorrentTrackers": .error(.conflict, code: "conflict", message: "Umbra says no."),
    ])
    await inspector.removeTrackers(["udp://t.example/a"])
    #expect(inspector.changeFailure == "Umbra says no.")
    // Switching tab clears the old line.
    inspector.tab = .peers
    #expect(inspector.changeFailure == nil)
  }

  @Test func askAgainReannouncesTheSelectedTorrent() async {
    let (inspector, _, transport) = setUp(["getTorrentTrackers": Sample.trackers])
    await inspector.askAgain()
    let post = await transport.sent.first { $0.operation == "torrentAction" }
    #expect(post?.json == ["action": "reannounce", "hashes": ["a1"]])
    #expect(inspector.changeFailure == nil)
  }

  @Test func askAgainFailureShowsInTheInspector() async {
    let (inspector, _, _) = setUp([
      "torrentAction": .error(.serviceUnavailable, code: "engine_down", message: "Engine down.")
    ])
    await inspector.askAgain()
    #expect(inspector.changeFailure == "Engine down.")
  }

  @Test func downloadAgainChecksTheFiles() async {
    let (inspector, _, transport) = setUp()
    await inspector.downloadAgain()
    let post = await transport.sent.first { $0.operation == "torrentAction" }
    #expect(post?.json == ["action": "recheck", "hashes": ["a1"]])
  }

  @Test func changesNeedAConnection() async {
    let (inspector, _, transport) = setUp(connected: false)
    #expect(await inspector.addTrackers("udp://x") == "Umbra isn't connected.")
    await inspector.askAgain()
    #expect(inspector.changeFailure == "Umbra isn't connected.")
    #expect(await transport.sent.isEmpty)
  }
}
