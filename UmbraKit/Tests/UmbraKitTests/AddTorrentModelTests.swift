import Foundation
import HTTPTypes
import Testing
import UmbraAPI

@testable import UmbraKit

/// The Add sheet's model: every state, what it sends, and the races
/// (slow answers, closing mid-request, Add pressed twice).
@MainActor @Suite struct AddTorrentModelTests {
  let connection = Connection(
    baseURL: URL(string: "http://127.0.0.1:7980")!, credential: .apiKey("key"))

  /// What the model under test selected in the list.
  final class Selected { var hashes: [[String]] = [] }

  func model(
    _ replies: [String: [RecordingTransport.Reply]] = [:], sleeper: TestSleeper = TestSleeper(),
    typingPause: Duration = .zero, tags: [String] = [], categories: [String] = []
  ) -> (AddTorrentModel, GatedTransport, Selected) {
    let transport = GatedTransport(replies)
    let selected = Selected()
    let model = AddTorrentModel(
      actions: TorrentActions(connection: connection, transport: transport),
      categories: categories, tags: tags, select: { selected.hashes.append($0) },
      typingPause: typingPause, sleep: { try await sleeper.sleep($0) })
    return (model, transport, selected)
  }

  let file = [(name: "sample.torrent", data: AddSample.fileBytes)]

  // MARK: Empty

  @Test func startsEmpty() {
    let (model, _, _) = model()
    #expect(model.phase == .empty)
    #expect(!model.canAdd)
    #expect(model.addTitle == "Add")
    #expect(model.fileTree == nil)
  }

  @Test func textThatIsntALinkSaysSoAndSendsNothing() async {
    let (model, transport, _) = model()
    model.linkText = "hello"
    #expect(model.linkNote != nil)
    #expect(model.phase == .empty)
    model.linkText = ""
    #expect(model.linkNote == nil)
    try? await Task.sleep(for: .milliseconds(20))
    #expect(await transport.sent.isEmpty)
  }

  // MARK: A .torrent file

  @Test func aTorrentFileIsInspectedAndShowsItsFiles() async throws {
    let (model, transport, _) = model(["inspectTorrent": [AddSample.torrentPreview]])
    await transport.hold("torrentFile")
    model.choose(files: file)
    #expect(model.phase == .inspecting)
    #expect(model.items.first?.label == "sample.torrent")
    await transport.release("torrentFile")
    #expect(await eventually { model.phase == .ready })
    let item = try #require(model.items.first)
    #expect(item.name == "Sample.Set")
    #expect(item.summary == "600 B · 3 files · 2 trackers")
    #expect(model.filesSummary == "3 files · 600 B")
    // Folders first, then names in Finder's order.
    #expect(
      model.visibleNodes.map(\.id) == [
        "Sample.Set", "Sample.Set/sub", "Sample.Set/sub/c.bin", "Sample.Set/a.bin",
        "Sample.Set/b.bin",
      ])
    #expect(await transport.sent("inspectTorrent").first?.torrentFileBytes == AddSample.fileBytes)
  }

  @Test func addingSendsTheChoicesExactlyAndSelectsTheNewTorrent() async throws {
    let (model, transport, selected) = model([
      "inspectTorrent": [AddSample.torrentPreview], "addTorrent": [AddSample.added()],
    ])
    model.choose(files: file)
    #expect(await eventually { model.phase == .ready })
    model.category = "films"
    model.addTag("new-tag,")
    model.addTag("keep")
    model.addTag("keep")
    model.startPaused = true
    // Untick the "sub" folder (c.bin) and a.bin; b.bin stays.
    let nodes = model.visibleNodes
    model.click(try #require(nodes.first { $0.id == "Sample.Set/sub" }))
    model.click(try #require(nodes.first { $0.id == "Sample.Set/a.bin" }))
    #expect(model.filesSummary == "3 files · 200 B of 600 B selected")
    #expect(model.visibleNodes.first?.tick == .mixed)

    await model.add()

    let sent = try #require(await transport.sent("addTorrent").first)
    #expect(sent.torrentFileBytes == AddSample.fileBytes)
    #expect(sent.json?["category"] as? String == "films")
    #expect(sent.json?["tags"] as? [String] == ["new-tag", "keep"])
    #expect(sent.json?["paused"] as? Bool == true)
    // In the torrent's own file order: b.bin, a.bin, sub/c.bin.
    #expect(sent.json?["filePriorities"] as? [String] == ["normal", "skip", "skip"])
    #expect(model.isFinished)
    #expect(selected.hashes == [[AddSample.fileHash]])
  }

  @Test func everyFileTickedSendsNoPriorities() async throws {
    let (model, transport, _) = model([
      "inspectTorrent": [AddSample.torrentPreview], "addTorrent": [AddSample.added()],
    ])
    model.choose(files: file)
    #expect(await eventually { model.phase == .ready })
    model.selectNone()
    #expect(model.visibleNodes.allSatisfy { $0.tick == .off })
    model.selectAll()
    await model.add()
    let sent = try #require(await transport.sent("addTorrent").first)
    #expect(sent.json?["filePriorities"] == nil)
    #expect(sent.json?["category"] == nil)
  }

  @Test func foldersOpenAndClose() async {
    let (model, _, _) = model(["inspectTorrent": [AddSample.torrentPreview]])
    model.choose(files: file)
    #expect(await eventually { model.phase == .ready })
    model.toggleFolder("Sample.Set/sub")
    #expect(!model.visibleNodes.contains { $0.id == "Sample.Set/sub/c.bin" })
    model.toggleFolder("Sample.Set/sub")
    #expect(model.visibleNodes.contains { $0.id == "Sample.Set/sub/c.bin" })
  }

  @Test func anUnreadableFileShowsWhyInItsPlace() {
    let (model, _, _) = model()
    model.choose(fileURLs: [URL(filePath: "/nonexistent/folder/missing.torrent")])
    #expect(model.phase == .refused)
    #expect(model.items.first?.label == "missing.torrent")
  }

  // MARK: Several files

  @Test func severalFilesAreAddedWholeWithTheSameChoices() async throws {
    let (model, transport, selected) = model([
      "inspectTorrent": [AddSample.torrentPreview],
      "addTorrent": [AddSample.added(), AddSample.added(AddSample.otherHash)],
    ])
    model.choose(files: file + [(name: "two.torrent", data: Data("two".utf8))])
    #expect(await eventually { model.items.allSatisfy(\.isNew) })
    // No file tree with several, as on the web page.
    #expect(model.fileTree == nil)
    model.addTag("x")
    #expect(model.addTitle == "Add 2 Torrents")
    await model.add()
    let sent = await transport.sent("addTorrent")
    #expect(sent.count == 2)
    #expect(sent.allSatisfy { $0.json?["tags"] as? [String] == ["x"] })
    #expect(sent.allSatisfy { $0.json?["filePriorities"] == nil })
    #expect(selected.hashes == [[AddSample.fileHash, AddSample.otherHash]])
  }

  @Test func oneOfSeveralRefusedKeepsTheSheetOpenAndSelectsTheOthersOnClose() async throws {
    let (model, _, selected) = model([
      "inspectTorrent": [AddSample.torrentPreview],
      "addTorrent": [
        AddSample.added(),
        .error(.unprocessableContent, code: "no_space", message: "There isn't enough space."),
      ],
    ])
    model.choose(files: file + [(name: "two.torrent", data: Data("two".utf8))])
    #expect(await eventually { model.newItems.count == 2 })
    #expect(model.addTitle == "Add 2 Torrents")
    await model.add()
    #expect(!model.isFinished)
    #expect(model.items[0].state == .added(AddSample.fileHash))
    #expect(model.items[1].state == .refused("There isn't enough space."))
    #expect(selected.hashes.isEmpty)
    model.close()
    #expect(selected.hashes == [[AddSample.fileHash]])
  }

  // MARK: A magnet link

  @Test func aMagnetWaitsForItsDetailsThenShowsItsFiles() async throws {
    let sleeper = TestSleeper()
    let (model, transport, _) = model(
      [
        "inspectTorrent": [AddSample.waiting()],
        "getWaitingTorrent": [AddSample.waiting(peers: 5), AddSample.magnetDetails],
      ], sleeper: sleeper)
    model.linkText = AddSample.magnet
    #expect(model.linkText == AddSample.magnet)
    #expect(await eventually { model.phase == .waitingForDetails })
    #expect(model.addTitle == "Add Now")
    #expect(model.canAdd)
    #expect(
      AddTorrentModel.waitingText(try #require(model.items.first))
        == "Fetching details… connected to 3 peers. The file list appears here as soon as it arrives."
    )
    #expect(model.fileTree == nil)
    #expect(await transport.sent("inspectTorrent").first?.json?["fetchDetails"] as? Bool == true)

    // Asked again a second later: still waiting, more peers.
    await sleeper.allow()
    #expect(await eventually { await transport.count("getWaitingTorrent") == 1 })
    #expect(await eventually { model.items.first?.preview?.peers == 5 })
    #expect(model.phase == .waitingForDetails)
    #expect(await sleeper.durations.first == .seconds(1))

    // Then the details: the tree fills in.
    await sleeper.allow()
    #expect(await eventually { model.phase == .ready })
    #expect(model.visibleNodes.map(\.name) == ["Some.Thing.iso"])
    #expect(model.addTitle == "Add")
    await sleeper.allow(5)
    try? await Task.sleep(for: .milliseconds(30))
    #expect(await transport.count("getWaitingTorrent") == 2)
  }

  @Test func aLinkFromOutsideFillsTheFieldAndAddsNothing() async {
    let (model, transport, _) = model(["inspectTorrent": [AddSample.waiting()]])
    model.choose(link: AddSample.magnet)
    #expect(model.linkText == AddSample.magnet)
    #expect(await eventually { model.phase == .waitingForDetails })
    #expect(await transport.count("addTorrent") == 0)
    #expect(!model.isFinished)
  }

  @Test func addNowAddsTheWaitingMagnetAndLeavesNothingToCancel() async throws {
    let (model, transport, selected) = model([
      "inspectTorrent": [AddSample.waiting()],
      "addTorrent": [AddSample.added(AddSample.magnetHash)],
    ])
    model.linkText = AddSample.magnet
    #expect(await eventually { model.phase == .waitingForDetails })
    model.startPaused = true
    await model.add()
    let sent = try #require(await transport.sent("addTorrent").first)
    #expect(sent.json == ["magnet": AddSample.magnet, "tags": [String](), "paused": true])
    #expect(model.isFinished)
    #expect(selected.hashes == [[AddSample.magnetHash]])
    try? await Task.sleep(for: .milliseconds(20))
    #expect(await transport.count("cancelWaitingTorrent") == 0)
  }

  @Test func closingCancelsTheWaitingMagnet() async {
    let (model, transport, selected) = model(["inspectTorrent": [AddSample.waiting()]])
    model.linkText = AddSample.magnet
    #expect(await eventually { model.phase == .waitingForDetails })
    model.close()
    model.close()
    #expect(await eventually { await transport.count("cancelWaitingTorrent") == 1 })
    #expect(
      await transport.sent("cancelWaitingTorrent").first?.path
        == "/torrents/inspect/\(AddSample.magnetHash)")
    #expect(selected.hashes.isEmpty)
    #expect(!model.canAdd)
  }

  @Test func closingWhileTheInspectIsOutStillCancelsWhatItStarted() async {
    let (model, transport, _) = model(["inspectTorrent": [AddSample.waiting()]])
    await transport.hold(AddSample.magnetHash)
    model.linkText = AddSample.magnet
    #expect(await eventually { await transport.count("inspectTorrent") == 1 })
    model.close()
    await transport.release(AddSample.magnetHash)
    #expect(await eventually { await transport.count("cancelWaitingTorrent") == 1 })
    // The late answer isn't shown.
    #expect(model.phase == .inspecting)
  }

  @Test func aWebAddressThatGaveAMagnetIsAddedWithIt() async throws {
    let gave = RecordingTransport.Reply.json(
      """
      {"hash":"\(AddSample.magnetHash)","name":"Some.Thing","detailsKnown":false,"private":false,
       "trackers":[],"waiting":true,"magnet":"\(AddSample.magnet)"}
      """)
    let (model, transport, _) = model([
      "inspectTorrent": [gave], "addTorrent": [AddSample.added(AddSample.magnetHash)],
    ])
    model.linkText = "http://127.0.0.1:1/get/42.torrent"
    #expect(await eventually { model.phase == .waitingForDetails })
    #expect(
      await transport.sent("inspectTorrent").first?.json?["url"] as? String
        == "http://127.0.0.1:1/get/42.torrent")
    await model.add()
    #expect(
      await transport.sent("addTorrent").first?.json?["magnet"] as? String == AddSample.magnet)
  }

  @Test func aMagnetUmbraForgotSaysToPasteItAgain() async {
    let sleeper = TestSleeper()
    let (model, _, _) = model(
      [
        "inspectTorrent": [AddSample.waiting()],
        "getWaitingTorrent": [.error(.notFound, code: "not_found", message: "Not waiting.")],
      ], sleeper: sleeper)
    model.linkText = AddSample.magnet
    #expect(await eventually { model.phase == .waitingForDetails })
    await sleeper.allow()
    #expect(await eventually { model.phase == .refused })
    #expect(
      model.items.first?.state
        == .refused("Umbra stopped waiting for this magnet link's details. Paste it again."))
  }

  // MARK: Replacing the source

  @Test func aSlowAnswerForAReplacedLinkIsIgnoredAndItsWaitCancelled() async throws {
    let (model, transport, _) = model([
      "inspectTorrent": [
        AddSample.waiting(), AddSample.waiting(AddSample.otherHash, name: "Other"),
      ]
    ])
    await transport.hold(AddSample.magnetHash)
    model.linkText = AddSample.magnet
    #expect(await eventually { await transport.count("inspectTorrent") == 1 })
    model.linkText = AddSample.otherMagnet
    #expect(await eventually { model.items.first?.name == "Other" })
    await transport.release(AddSample.magnetHash)
    // The first link's late answer is dropped, and its wait called off.
    #expect(await eventually { await transport.count("cancelWaitingTorrent") == 1 })
    #expect(model.items.count == 1)
    #expect(model.items.first?.name == "Other")
    #expect(
      await transport.sent("cancelWaitingTorrent").first?.path
        == "/torrents/inspect/\(AddSample.magnetHash)")
  }

  @Test func choosingFilesReplacesTheLinkAndCancelsItsWait() async {
    let (model, transport, _) = model([
      "inspectTorrent": [AddSample.waiting(), AddSample.torrentPreview]
    ])
    model.linkText = AddSample.magnet
    #expect(await eventually { model.phase == .waitingForDetails })
    model.choose(files: file)
    #expect(model.linkText.isEmpty)
    #expect(await eventually { model.phase == .ready })
    #expect(await eventually { await transport.count("cancelWaitingTorrent") == 1 })
    #expect(model.items.map(\.label) == ["sample.torrent"])
  }

  @Test func typingWaitsForAPauseAndLooksOnlyAtTheLast() async {
    let sleeper = TestSleeper()
    let (model, transport, _) = model(
      ["inspectTorrent": [AddSample.torrentPreview]], sleeper: sleeper,
      typingPause: .milliseconds(350))
    model.linkText = "http://127.0.0.1:1/a"
    model.linkText = "http://127.0.0.1:1/a.torrent"
    #expect(model.phase == .empty)
    await sleeper.allow(2)
    #expect(await eventually { model.phase == .ready })
    let sent = await transport.sent("inspectTorrent")
    #expect(sent.count == 1)
    #expect(sent.first?.json?["url"] as? String == "http://127.0.0.1:1/a.torrent")
    #expect(await sleeper.durations.first == .milliseconds(350))
  }

  // MARK: Refusals

  @Test func aRefusedFileShowsUmbrasWordsForTheField() async {
    let (model, _, _) = model(["inspectTorrent": [AddSample.badFile]])
    model.choose(files: file)
    #expect(await eventually { model.phase == .refused })
    #expect(model.items.first?.state == .refused("This isn't a .torrent file."))
    #expect(!model.canAdd)
  }

  @Test func aRefusedLinkKeepsWhatWasTyped() async {
    let (model, _, _) = model([
      "inspectTorrent": [
        .error(.unprocessableContent, code: "fetch", message: "That address couldn't be fetched.")
      ]
    ])
    model.linkText = "http://127.0.0.1:1/missing.torrent"
    #expect(await eventually { model.phase == .refused })
    #expect(model.items.first?.state == .refused("That address couldn't be fetched."))
    #expect(model.linkText == "http://127.0.0.1:1/missing.torrent")
  }

  @Test func aRefusedAddStaysOpenWithTheChoicesAndCanBeTriedAgain() async throws {
    let (model, transport, selected) = model([
      "inspectTorrent": [AddSample.torrentPreview],
      "addTorrent": [
        .error(.serviceUnavailable, code: "engine_down", message: "The engine isn't running."),
        AddSample.added(),
      ],
    ])
    model.choose(files: file)
    #expect(await eventually { model.phase == .ready })
    model.addTag("keep")
    await model.add()
    #expect(model.phase == .refused)
    #expect(model.addFailure == "The engine isn't running.")
    #expect(!model.isFinished)
    #expect(model.tags == ["keep"])
    #expect(model.canAdd)
    await model.add()
    #expect(model.isFinished)
    #expect(await transport.count("addTorrent") == 2)
    #expect(selected.hashes == [[AddSample.fileHash]])
  }

  // MARK: Already in the list

  @Test func aDuplicateOffersItsNewTrackersThenSelectsTheExistingTorrent() async throws {
    let (model, transport, selected) = model(["inspectTorrent": [AddSample.duplicate]])
    model.choose(files: file)
    #expect(await eventually { model.phase == .duplicate })
    #expect(!model.canAdd)
    let existing = try #require(model.duplicate?.existing)
    #expect(existing.newTrackers == ["udp://tracker.invalid/b"])
    #expect(
      model.duplicateText
        == "Sample.Set is already in your list (seeding). It has 1 tracker that the existing torrent doesn’t."
    )
    await model.addTrackersToExisting()
    let sent = try #require(await transport.sent("addTorrentTrackers").first)
    #expect(sent.path == "/torrents/\(AddSample.fileHash)/trackers")
    #expect(sent.json == ["urls": ["udp://tracker.invalid/b"]])
    #expect(model.isFinished)
    #expect(selected.hashes == [[AddSample.fileHash]])
    #expect(await transport.count("addTorrent") == 0)
  }

  @Test func aDuplicateCanJustBeShownInTheList() async {
    let (model, transport, selected) = model(["inspectTorrent": [AddSample.duplicate]])
    model.choose(files: file)
    #expect(await eventually { model.phase == .duplicate })
    model.showExisting()
    #expect(model.isFinished)
    #expect(selected.hashes == [[AddSample.fileHash]])
    #expect(await transport.count("addTorrentTrackers") == 0)
  }

  @Test func aTrackerRefusalStaysInTheSheet() async {
    let (model, _, selected) = model([
      "inspectTorrent": [AddSample.duplicate],
      "addTorrentTrackers": [.error(.notFound, code: "not_found", message: "It's gone.")],
    ])
    model.choose(files: file)
    #expect(await eventually { model.phase == .duplicate })
    await model.addTrackersToExisting()
    #expect(model.trackerFailure == "It's gone.")
    #expect(!model.isFinished)
    #expect(selected.hashes.isEmpty)
  }

  // MARK: Add pressed twice

  @Test func pressingAddTwiceAddsOnce() async {
    let (model, transport, selected) = model([
      "inspectTorrent": [AddSample.torrentPreview], "addTorrent": [AddSample.added()],
    ])
    model.choose(files: file)
    #expect(await eventually { model.phase == .ready })
    await transport.hold("torrentFile")
    async let first: Void = model.add()
    async let second: Void = model.add()
    #expect(await eventually { model.phase == .adding })
    #expect(!model.canAdd)
    await transport.release("torrentFile")
    _ = await (first, second)
    #expect(await transport.count("addTorrent") == 1)
    #expect(selected.hashes == [[AddSample.fileHash]])
  }

  // MARK: Options

  @Test func categoriesAndTheSaveFolder() async {
    let (model, _, _) = model(
      ["getDownloadsSettings": [AddSample.folders]], tags: ["b", "a"], categories: ["films", "tv"])
    #expect(model.saveFolder == nil)
    await model.loadFolders()
    #expect(model.categories == ["films", "books", "tv"])
    #expect(model.saveFolder == "/data/downloads")
    model.category = "films"
    #expect(model.saveFolder == "/data/films")
    #expect(model.tagSuggestions == ["a", "b"])
    model.addTag(" a ")
    model.addTag("")
    #expect(model.tags == ["a"])
    #expect(model.tagSuggestions == ["b"])
    model.removeTag("a")
    #expect(model.tags.isEmpty)
  }
}

/// Selecting what the sheet added once the live feed brings it.
@MainActor @Suite struct SelectWhenListedTests {
  @Test func selectsATorrentAlreadyListedAtOnce() {
    let (model, _) = makeModel(defaults: throwawayDefaults())
    model.selectWhenListed(["c3"])
    #expect(model.selection == ["c3"])
  }

  @Test func waitsForTheNewRowThenShowsAndSelectsIt() async {
    let (model, store) = makeModel(defaults: throwawayDefaults())
    model.filter = .tag("keep")
    model.searchText = "Del"
    model.selectWhenListed(["n9"])
    #expect(model.selection.isEmpty)
    store.patch([torrent("n9", name: "New") { $0.state = .downloading }])
    #expect(await eventually { model.selection == ["n9"] })
    // The filter and search would hide it, so the list shows everything.
    #expect(model.filter == .all)
    #expect(model.searchText.isEmpty)
  }
}
