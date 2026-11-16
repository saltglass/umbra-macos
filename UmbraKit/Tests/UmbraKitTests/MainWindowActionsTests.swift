import Foundation
import Testing
import UmbraAPI

@testable import UmbraKit

/// The window model's torrent commands, against the stand-in network.
@MainActor @Suite struct MainWindowActionsTests {
  let connection = Connection(
    baseURL: URL(string: "http://127.0.0.1:7980")!, credential: .apiKey("key"))

  func setUp(_ replies: [String: RecordingTransport.Reply] = [:]) -> (
    MainWindowModel, TorrentStore, TorrentActions, RecordingTransport
  ) {
    let (model, store) = makeModel(defaults: throwawayDefaults())
    let transport = RecordingTransport(replies)
    return (model, store, TorrentActions(connection: connection, transport: transport), transport)
  }

  static let refused = RecordingTransport.Reply.error(
    .conflict, code: "nope", message: "Umbra said no.")

  // MARK: The menu

  @Test func theMenuIsForTheSelectionInListOrder() {
    let (model, _, _, _) = setUp()
    model.selection = ["d4", "a1"]
    // The default sort shows the newest first: Delta, Charlie, Bravo, Alpha.
    #expect(model.selectedRows.map(\.id) == ["d4", "a1"])
    // A right-click on one unselected row offers a menu for just that row.
    let menu = model.torrentMenu(for: ["b2"], connected: true)
    #expect(menu.item("Pause")?.enabled == true)
    #expect(menu.item("Resume")?.enabled == false)
  }

  @Test func theMenuOffersDefinedAndInUseCategoriesAndTagsInUse() {
    let (model, _, _, _) = setUp()
    model.definedCategories = ["books"]
    let items = model.torrentMenu(connected: true).submenu("Category").flatMap(\.allItems)
    #expect(items.map(\.title) == ["None", "books", "films"])  // films is in use by Alpha
    let tags = model.torrentMenu(connected: true).submenu("Tags").flatMap(\.allItems)
    #expect(tags.map(\.title) == ["keep", "New Tag…"])  // keep is on Delta
  }

  @Test func theMenuIsDimmedWithNothingSelectedOrNotConnected() {
    let (model, _, _, _) = setUp()
    #expect(model.torrentMenu(connected: true).item("Remove…")?.enabled == false)
    model.selection = ["a1"]
    #expect(model.torrentMenu(connected: true).item("Remove…")?.enabled == true)
    #expect(model.torrentMenu(connected: false).item("Remove…")?.enabled == false)
  }

  @Test func theToolbarsPauseAndResumeFollowTheSelection() {
    let (model, _, actions, _) = setUp()
    #expect(!model.canPause(with: actions))
    model.selection = ["d4"]  // paused
    #expect(!model.canPause(with: actions))
    #expect(model.canResume(with: actions))
    #expect(!model.canResume(with: nil))
    model.selection = ["a1"]
    #expect(model.canPause(with: actions))
    #expect(!model.canResume(with: actions))
  }

  // MARK: Space

  @Test func spaceBarPausesRunningTorrents() async throws {
    let (model, _, actions, transport) = setUp()
    model.selection = ["a1", "d4"]
    #expect(model.spaceBar(using: actions))
    await settle()
    let sent = try #require(await transport.sent.first)
    #expect(sent.json?["action"] as? String == "pause")
  }

  @Test func spaceBarResumesWhenAllAreStopped() async throws {
    let (model, _, actions, transport) = setUp()
    model.selection = ["d4"]
    #expect(model.spaceBar(using: actions))
    await settle()
    #expect(try #require(await transport.sent.first).json?["action"] as? String == "resume")
  }

  @Test func spaceBarDoesNothingWithoutASelectionOrUmbra() async {
    let (model, _, actions, transport) = setUp()
    #expect(!model.spaceBar(using: actions))
    model.selection = ["a1"]
    #expect(!model.spaceBar(using: nil))
    await settle()
    #expect(await transport.sent.isEmpty)
  }

  // MARK: Category and tags

  @Test func setsTheCategoryOfTheSelection() async throws {
    let (model, _, actions, transport) = setUp()
    model.selection = ["b2", "c3"]
    await model.setCategory("films", using: actions)
    let sent = try #require(await transport.sent.first)
    #expect(sent.operation == "setTorrentsCategory")
    #expect(sent.json == ["hashes": ["c3", "b2"], "category": "films"])
    #expect(model.actionFailure == nil)
  }

  @Test func noneClearsTheCategory() async throws {
    let (model, _, actions, transport) = setUp()
    model.selection = ["a1"]
    await model.setCategory("", using: actions)
    #expect(try #require(await transport.sent.first).json?["category"] as? String == "")
  }

  @Test func aCategoryFailureBecomesAnAlert() async {
    let (model, _, actions, _) = setUp(["setTorrentsCategory": Self.refused])
    model.selection = ["a1", "b2"]
    await model.setCategory("films", using: actions)
    #expect(
      model.actionFailure
        == ActionFailure(
          title: "Couldn't change the category of 2 torrents", message: "Umbra said no."))
  }

  @Test func addsAndRemovesTags() async throws {
    let (model, _, actions, transport) = setUp()
    model.selection = ["a1", "d4"]
    await model.changeTag("keep", add: true, using: actions)
    await model.changeTag("old", add: false, using: actions)
    let sent = await transport.sent
    #expect(sent.map(\.operation) == ["setTorrentsTags", "setTorrentsTags"])
    #expect(sent[0].json == ["hashes": ["d4", "a1"], "add": ["keep"]])
    #expect(sent[1].json == ["hashes": ["d4", "a1"], "remove": ["old"]])
  }

  @Test func aNewTagIsTrimmedAndAnEmptyOneIgnored() async throws {
    let (model, _, actions, transport) = setUp()
    model.selection = ["a1"]
    await model.changeTag("  fresh ", add: true, using: actions)
    await model.changeTag("   ", add: true, using: actions)
    let sent = await transport.sent
    #expect(sent.count == 1)
    #expect(sent[0].json?["add"] as? [String] == ["fresh"])
  }

  @Test func aTagFailureBecomesAnAlert() async {
    let (model, _, actions, _) = setUp(["setTorrentsTags": Self.refused])
    model.selection = ["a1"]
    await model.changeTag("x", add: true, using: actions)
    #expect(model.actionFailure?.title == "Couldn't change the tags of the torrent")
    #expect(model.actionFailure?.message == "Umbra said no.")
  }

  @Test func theCategoriesCommandsDoNothingWithoutASelectionOrUmbra() async {
    let (model, _, actions, transport) = setUp()
    await model.setCategory("films", using: actions)
    model.selection = ["a1"]
    await model.setCategory("films", using: nil)
    await model.changeTag("x", add: true, using: nil)
    #expect(await transport.sent.isEmpty)
  }

  // MARK: Remove

  @Test func theConfirmationNamesTheSelection() throws {
    let (model, _, _, _) = setUp()
    #expect(model.removeConfirmation() == nil)
    model.selection = ["a1"]
    #expect(try #require(model.removeConfirmation()).title == "Remove “Alpha”?")
    model.selection = ["a1", "b2", "c3"]
    #expect(try #require(model.removeConfirmation()).title == "Remove 3 torrents?")
  }

  @Test func removeKeepsTheFilesUnlessAskedOtherwise() async throws {
    let (model, _, actions, transport) = setUp()
    model.selection = ["a1", "b2"]
    let confirmation = try #require(model.removeConfirmation())
    await model.remove(confirmation, deleteFiles: false, using: actions)
    let sent = try #require(await transport.sent.first)
    #expect(sent.operation == "removeTorrents")
    #expect(sent.json == ["hashes": ["b2", "a1"], "deleteFiles": false])
  }

  @Test func removeCanDeleteTheFiles() async throws {
    let (model, _, actions, transport) = setUp()
    model.selection = ["c3"]
    await model.remove(try #require(model.removeConfirmation()), deleteFiles: true, using: actions)
    #expect(
      try #require(await transport.sent.first).json == ["hashes": ["c3"], "deleteFiles": true])
  }

  @Test func removeActsOnWhatTheAlertNamedEvenIfTheSelectionMovedOn() async throws {
    let (model, _, actions, transport) = setUp()
    model.selection = ["a1"]
    let confirmation = try #require(model.removeConfirmation())
    model.selection = ["b2", "c3"]
    await model.remove(confirmation, deleteFiles: false, using: actions)
    #expect(try #require(await transport.sent.first).json?["hashes"] as? [String] == ["a1"])
  }

  @Test func aRemoveFailureBecomesAnAlert() async throws {
    let (model, _, actions, _) = setUp(["removeTorrents": Self.refused])
    model.selection = ["a1", "b2", "c3"]
    await model.remove(try #require(model.removeConfirmation()), deleteFiles: true, using: actions)
    #expect(
      model.actionFailure
        == ActionFailure(title: "Couldn't remove 3 torrents", message: "Umbra said no."))
  }

  // MARK: Copying

  @Test func copiesInfoHashesOnePerLine() async {
    let (model, _, actions, transport) = setUp()
    model.selection = ["c3", "a1"]
    #expect(await model.copyText(.infoHashes, using: actions) == "c3\na1")
    #expect(await transport.sent.isEmpty)
  }

  @Test func copiesMagnetLinksOnePerLine() async {
    let (model, _, actions, transport) = setUp([
      "getTorrentMagnet": .json(#"{"magnet":"magnet:?xt=1"}"#)
    ])
    model.selection = ["a1", "b2"]
    #expect(await model.copyText(.magnetLinks, using: actions) == "magnet:?xt=1\nmagnet:?xt=1")
    #expect(await transport.sent.map(\.path) == ["/torrents/b2/magnet", "/torrents/a1/magnet"])
  }

  @Test func aMagnetFailureBecomesAnAlertAndCopiesNothing() async {
    let (model, _, actions, _) = setUp(["getTorrentMagnet": Self.refused])
    model.selection = ["a1"]
    #expect(await model.copyText(.magnetLinks, using: actions) == nil)
    #expect(model.actionFailure?.title == "Couldn't copy the magnet link of the torrent")
  }

  // MARK: Exporting

  static let torrentFile = RecordingTransport.Reply(
    status: .ok, contentType: "application/x-bittorrent", body: "d4:infoe")

  func tempFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "umbra-export-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func exportsOneTorrentToTheChosenFile() async throws {
    let (model, _, actions, transport) = setUp(["exportTorrentFile": Self.torrentFile])
    let folder = try tempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    model.selection = ["b2"]
    let file = folder.appending(path: "Bravo.torrent")
    #expect(await model.exportTorrents(to: file, using: actions))
    #expect(try Data(contentsOf: file) == Data("d4:infoe".utf8))
    #expect(await transport.sent.map(\.path) == ["/torrents/b2/file"])
  }

  @Test func exportsSeveralIntoAFolderNamedAfterEach() async throws {
    let (model, _, actions, transport) = setUp(["exportTorrentFile": Self.torrentFile])
    let folder = try tempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    // A file already there is never overwritten.
    try Data().write(to: folder.appending(path: "Alpha.torrent"))
    model.selection = ["a1", "c3"]
    #expect(await model.exportTorrents(to: folder, using: actions))
    let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    #expect(names == ["Alpha 2.torrent", "Alpha.torrent", "Charlie.torrent"])
    #expect(await transport.sent.count == 2)
  }

  @Test func anExportFailureBecomesAnAlert() async throws {
    let (model, _, actions, _) = setUp(["exportTorrentFile": Self.refused])
    model.selection = ["a1"]
    let folder = try tempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(!(await model.exportTorrents(to: folder.appending(path: "x.torrent"), using: actions)))
    #expect(model.actionFailure?.title == "Couldn't export the .torrent file of the torrent")
    #expect(model.actionFailure?.message == "Umbra said no.")
  }

  @Test func aFolderThatCantBeWrittenToBecomesAnAlertToo() async throws {
    let (model, _, actions, _) = setUp(["exportTorrentFile": Self.torrentFile])
    model.selection = ["a1"]
    let missing = FileManager.default.temporaryDirectory.appending(
      path: "no-such-\(UUID())/x.torrent")
    #expect(!(await model.exportTorrents(to: missing, using: actions)))
    #expect(model.actionFailure?.title == "Couldn't save the .torrent file of the torrent")
  }

  // MARK: Categories from Umbra

  @Test func readsTheCategoriesUmbraHasSetUp() async {
    let (model, _, actions, transport) = setUp([
      "getDownloadsSettings": .json(
        #"{"folder":"","incompleteFolder":"","categories":[{"name":"films","folder":""},{"name":"books","folder":""}]}"#
      )
    ])
    await model.refreshCategories(using: actions)
    #expect(model.definedCategories == ["films", "books"])
    #expect(await transport.sent.map(\.operation) == ["getDownloadsSettings"])
  }

  @Test func aFailedReadKeepsTheCategoriesAsTheyWere() async {
    let (model, _, actions, _) = setUp(["getDownloadsSettings": Self.refused])
    model.definedCategories = ["films"]
    await model.refreshCategories(using: actions)
    #expect(model.definedCategories == ["films"])
    #expect(model.actionFailure == nil)
  }

  @Test func aSettingsChangeIsCountedAndOtherListenersStillHearIt() {
    let store = TorrentStore()
    var heard: [String] = []
    let other = store.listenForSettingsChanges { heard.append($0) }
    let model = MainWindowModel(store: store, defaults: throwawayDefaults())
    store.announceSettingsChanged("downloads")
    #expect(model.settingsChangeCount == 1)
    #expect(heard == ["downloads"])
    other.cancel()
  }

  // MARK: Slow mode

  static let speed = TorrentActionsTests.speed

  func modelShowing(slowMode: Bool) -> (MainWindowModel, TorrentStore) {
    var feed = FeedState()
    feed.applySnapshot(.init(rev: 1, torrents: sampleTorrents()))
    var totals = transfer()
    totals.slowMode = slowMode
    feed.transfer = totals
    let store = TorrentStore.fixture(feed)
    return (MainWindowModel(store: store, defaults: throwawayDefaults()), store)
  }

  @Test func slowModeFollowsTheFeed() {
    #expect(!modelShowing(slowMode: false).0.slowMode)
    #expect(modelShowing(slowMode: true).0.slowMode)
  }

  @Test func slowModeIsOffBeforeTheFirstTotals() {
    let (model, _) = makeModel(defaults: throwawayDefaults())
    #expect(!model.slowMode)
    #expect(!model.torrentMenu(connected: true).slowMode.isTicked)
  }

  @Test func slowModeChangesFollowNewTotals() {
    let (model, store) = modelShowing(slowMode: false)
    var totals = transfer()
    totals.slowMode = true
    store.receive(.event(.transfer(totals)))
    store.flush()
    #expect(model.slowMode)
    #expect(model.torrentMenu(connected: true).slowMode.isTicked)
  }

  @Test func turningSlowModeOnShowsAtOnceThenTheFeedTakesOver() async throws {
    let on = Self.speed.replacingOccurrences(of: "false", with: "true")
    let (model, store) = modelShowing(slowMode: false)
    let transport = RecordingTransport([
      "getSpeedSettings": .json(Self.speed), "putSpeedSettings": .json(on),
    ])
    let actions = TorrentActions(connection: connection, transport: transport)
    await model.setSlowMode(true, using: actions)
    #expect(await transport.sent.map(\.operation) == ["getSpeedSettings", "putSpeedSettings"])
    #expect(model.slowMode)
    // The next totals (here, saying it is still off: someone turned it off
    // again) are the truth.
    var totals = transfer()
    totals.downSpeed = 99
    store.receive(.event(.transfer(totals)))
    store.flush()
    #expect(!model.slowMode)
  }

  @Test func aSlowModeFailureBecomesAnAlertAndChangesNothing() async {
    let (model, _) = modelShowing(slowMode: false)
    let transport = RecordingTransport(["getSpeedSettings": Self.refused])
    await model.setSlowMode(
      true, using: TorrentActions(connection: connection, transport: transport))
    #expect(!model.slowMode)
    #expect(
      model.actionFailure
        == ActionFailure(title: "Couldn't turn slow mode on", message: "Umbra said no."))
  }

  // MARK: Failure titles

  @Test func failureTitlesCoverTheNewActions() {
    #expect(
      ActionFailure(verb: "remove", count: 1, message: "").title == "Couldn't remove the torrent")
    #expect(
      ActionFailure(verb: "remove", count: 3, message: "").title == "Couldn't remove 3 torrents")
    #expect(
      ActionFailure(action: .recheck, count: 2, message: "").title == "Couldn't verify 2 torrents")
  }
}

extension TorrentMenuEntry {
  /// For a ticked item: whether its tick is on.
  var isTicked: Bool {
    if case .item(let item) = self { return item.mark == .on }
    return false
  }
}
