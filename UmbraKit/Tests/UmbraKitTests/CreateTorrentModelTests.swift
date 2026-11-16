import Foundation
import HTTPTypes
import Testing
import UmbraAPI

@testable import UmbraKit

/// Made-up answers from Umbra about making torrents. Paths and names are
/// invented; no tracker address in them is ever contacted.
enum CreateSample {
  static let hash = String(repeating: "c", count: 40)
  static let folder = "/Users/someone/Share/Holiday.Photos"

  static let preview = RecordingTransport.Reply.json(
    """
    {"name":"Holiday.Photos","files":12,"size":44342419456,"pieceLength":16777216,"pieces":2643}
    """)

  static func creation(
    id: String = "abc123", state: String = "queued", read: Int64 = 0, seeding: Bool = false,
    error: String? = nil, hash: String? = nil, size: Int64 = 1000
  ) -> String {
    var json =
      """
      {"id":"\(id)","name":"Holiday.Photos","path":"\(folder)","state":"\(state)","files":12,
       "size":\(size),"read":\(read),"pieceLength":16777216,"pieces":2643,"private":false,
       "seeding":\(seeding),"started":"2026-11-14T10:00:00Z"
      """
    if let error { json += ",\"error\":\"\(error)\"" }
    if let hash { json += ",\"hash\":\"\(hash)\"" }
    return json + "}"
  }

  static func created(_ state: String = "queued") -> RecordingTransport.Reply {
    .json(creation(state: state), status: .created)
  }

  /// Umbra's refusal naming fields, as it sends one.
  static func refusal(_ fields: [String: String]) -> RecordingTransport.Reply {
    let pairs = fields.map { "\"\($0.key)\":\"\($0.value)\"" }.joined(separator: ",")
    return .json(
      "{\"code\":\"invalid\",\"message\":\"Check the form.\",\"fields\":{\(pairs)}}",
      status: .unprocessableContent)
  }

  static func record(
    _ id: String = "abc123", state: Components.Schemas.Creation.statePayload = .reading,
    read: Int64 = 0, size: Int64 = 1000, seeding: Bool = false, error: String? = nil,
    hash: String? = nil
  ) -> Components.Schemas.Creation {
    .init(
      id: id, name: "Holiday.Photos", path: folder, state: state, files: 12, size: size,
      read: read, pieceLength: 16_777_216, pieces: 2643, _private: false, error: error,
      hash: hash, seeding: seeding, started: Date(timeIntervalSince1970: 1_780_000_000))
  }
}

@MainActor @Suite struct CreateTorrentModelTests {
  let connection = Connection(
    baseURL: URL(string: "http://127.0.0.1:7980")!, credential: .apiKey("key"))

  final class Selected { var hashes: [[String]] = [] }

  func model(_ replies: [String: [RecordingTransport.Reply]] = [:]) -> (
    CreateTorrentModel, GatedTransport, Selected
  ) {
    let transport = GatedTransport(replies)
    let selected = Selected()
    let model = CreateTorrentModel(
      actions: CreateTorrentActions(connection: connection, transport: transport),
      select: { selected.hashes.append($0) })
    return (model, transport, selected)
  }

  /// A model with a folder chosen and its preview shown.
  func readyModel(_ replies: [String: [RecordingTransport.Reply]] = [:]) async -> (
    CreateTorrentModel, GatedTransport, Selected
  ) {
    var all = replies
    if all["previewCreation"] == nil { all["previewCreation"] = [CreateSample.preview] }
    let made = model(all)
    made.0.choose(url: URL(fileURLWithPath: CreateSample.folder))
    _ = await eventually { made.0.previewSummary != nil }
    return made
  }

  // MARK: Tracker text

  @Test func trackerTextIsReadAsTiers() {
    #expect(TrackerText.tiers(from: "") == [])
    #expect(TrackerText.tiers(from: "  \n\n \n") == [])
    #expect(TrackerText.tiers(from: "udp://a.invalid:80") == [["udp://a.invalid:80"]])
    // No blank line: one tier.
    #expect(
      TrackerText.tiers(from: "udp://a.invalid\nudp://b.invalid") == [
        ["udp://a.invalid", "udp://b.invalid"]
      ])
    // A blank line starts a new tier; several in a row count as one; lines are trimmed.
    #expect(
      TrackerText.tiers(
        from: "\n  udp://a.invalid  \n\n\n\t\nhttps://b.invalid/announce\r\nudp://c.invalid\n\n")
        == [["udp://a.invalid"], ["https://b.invalid/announce", "udp://c.invalid"]])
  }

  @Test func aBadLineIsNotJudgedHere() {
    // Umbra decides what is a tracker; the box only splits lines.
    #expect(TrackerText.tiers(from: "not a tracker") == [["not a tracker"]])
  }

  // MARK: Choosing and the preview

  @Test func startsEmptyAndCannotCreate() {
    let (model, _, _) = model()
    #expect(model.phase == .editing)
    #expect(!model.canCreate)
    #expect(model.startSeeding)
    #expect(model.pieceSize == .automatic)
    #expect(model.pathProblem == nil)
  }

  @Test func choosingAskesUmbraForAPreviewOfThePath() async throws {
    let (model, transport, _) = await readyModel()
    let sent = try #require(await transport.sent("previewCreation").first)
    #expect(sent.json?["path"] as? String == CreateSample.folder)
    // Automatic sends no piece size.
    #expect(sent.json?["pieceLength"] == nil)
    #expect(model.previewSummary == "12 files, 41.3 GB, 2,643 pieces of 16 MB")
    #expect(model.chosenName == "Holiday.Photos")
    #expect(model.canCreate)
  }

  @Test func createWaitsForThePreview() async {
    let (model, transport, _) = model(["previewCreation": [CreateSample.preview]])
    await transport.hold("previewCreation")
    model.choose(url: URL(fileURLWithPath: CreateSample.folder))
    #expect(model.previewState == .looking)
    #expect(!model.canCreate)
    await model.create()
    #expect(await transport.sent("createTorrent").isEmpty)
    await transport.release("previewCreation")
    #expect(await eventually { model.canCreate })
  }

  @Test func aRefusedPreviewShowsUmbrasWordsAndBlocksCreate() async {
    let words = "That is your home folder. Choose a folder inside it instead."
    let (model, _, _) = model([
      "previewCreation": [CreateSample.refusal(["path": words])]
    ])
    model.choose(url: URL(fileURLWithPath: "/Users/someone"))
    #expect(await eventually { model.pathProblem != nil })
    #expect(model.pathProblem == words)
    #expect(model.problem(.path) == words)
    #expect(!model.canCreate)
  }

  @Test func aRefusalWithoutAFieldIsShownToo() async {
    let (model, _, _) = model([
      "previewCreation": [.error(.badRequest, code: "bad", message: "Umbra says no.")]
    ])
    model.choose(url: URL(fileURLWithPath: "/x"))
    #expect(await eventually { model.pathProblem == "Umbra says no." })
  }

  @Test func changingThePieceSizeAsksAgain() async throws {
    let (model, transport, _) = await readyModel()
    model.pieceSize = PieceSizeChoice.mb(4)
    #expect(await eventually { await transport.count("previewCreation") == 2 })
    let second = try #require(await transport.sent("previewCreation").last)
    #expect(second.json?["pieceLength"] as? Int == 4 << 20)
    #expect(second.json?["path"] as? String == CreateSample.folder)
  }

  @Test func theLastChoiceWinsWhenAnswersComeBackOutOfOrder() async {
    let (model, transport, _) = model([
      "previewCreation": [
        .json(#"{"name":"First","files":1,"size":10,"pieceLength":16384,"pieces":1}"#),
        .json(#"{"name":"Second","files":2,"size":20,"pieceLength":16384,"pieces":2}"#),
      ]
    ])
    await transport.hold("/first")
    model.choose(url: URL(fileURLWithPath: "/first"))
    #expect(await eventually { await transport.count("previewCreation") == 1 })
    model.choose(url: URL(fileURLWithPath: "/second"))
    #expect(await eventually { model.chosenName == "Second" })
    await transport.release("/first")
    try? await Task.sleep(for: .milliseconds(40))
    #expect(model.chosenName == "Second")
  }

  @Test func anythingButAFileAddressIsIgnored() {
    let (model, _, _) = model()
    model.choose(url: URL(string: "https://example.org/a")!)
    #expect(model.previewState == .none)
  }

  // MARK: What is sent

  @Test func createSendsEveryOption() async throws {
    let (model, transport, _) = await readyModel(["createTorrent": [CreateSample.created()]])
    model.trackersText = "udp://a.invalid:80\nhttps://b.invalid/announce\n\n  udp://c.invalid  \n"
    model.isPrivate = true
    model.comment = "  Made for a test  "
    model.source = "TEST"
    model.pieceSize = PieceSizeChoice.mb(4)
    model.startSeeding = false
    // Changing the piece size asks Umbra for a new preview first.
    #expect(await eventually { model.canCreate })
    await model.create()
    let sent = try #require(await transport.sent("createTorrent").first)
    #expect(sent.path.hasSuffix("/creations"))
    #expect(sent.json?["path"] as? String == CreateSample.folder)
    #expect(
      sent.json?["trackers"] as? [[String]] == [
        ["udp://a.invalid:80", "https://b.invalid/announce"], ["udp://c.invalid"],
      ])
    #expect(sent.json?["private"] as? Bool == true)
    #expect(sent.json?["comment"] as? String == "Made for a test")
    #expect(sent.json?["source"] as? String == "TEST")
    #expect(sent.json?["pieceLength"] as? Int == 4 << 20)
    #expect(sent.json?["seed"] as? Bool == false)
    // The Mac app never uses uploads or the folder browser.
    #expect(await transport.count("startUpload") == 0)
    #expect(await transport.count("listFolder") == 0)
  }

  @Test func createWithDefaultsSendsOnlyWhatWasChosen() async throws {
    let (model, transport, _) = await readyModel(["createTorrent": [CreateSample.created()]])
    await model.create()
    let sent = try #require(await transport.sent("createTorrent").first)
    #expect(sent.json?["path"] as? String == CreateSample.folder)
    #expect(sent.json?["trackers"] == nil)
    #expect(sent.json?["comment"] == nil)
    #expect(sent.json?["source"] == nil)
    #expect(sent.json?["pieceLength"] == nil)
    #expect(sent.json?["private"] as? Bool == false)
    #expect(sent.json?["seed"] as? Bool == true)
    #expect(sent.json?["category"] == nil)
    #expect(sent.json?["tags"] == nil)
  }

  @Test func privateStartsTickedOnceThereAreTrackersUntilChosenByHand() {
    let (model, _, _) = model()
    #expect(!model.isPrivate)
    model.trackersText = "udp://a.invalid"
    #expect(model.isPrivate)
    model.isPrivate = false
    #expect(!model.isPrivate)
    model.trackersText = ""
    model.isPrivate = true
    model.trackersText = ""
    #expect(model.isPrivate)
  }

  // MARK: Refusals

  @Test func aRefusalShowsUnderItsFieldAndKeepsEverything() async {
    let words = "udp:/bad isn't a tracker's address (they start with http://, https:// or udp://)."
    let (model, _, _) = await readyModel([
      "createTorrent": [CreateSample.refusal(["trackers": words, "comment": "Too long."])]
    ])
    model.trackersText = "udp:/bad"
    model.comment = "hello"
    await model.create()
    #expect(model.phase == .editing)
    #expect(model.problem(.trackers) == words)
    #expect(model.problem(.comment) == "Too long.")
    #expect(model.problem(.source) == nil)
    #expect(model.generalFailure == nil)
    // Nothing was lost: the choice, its preview and the typing are still here.
    #expect(model.trackersText == "udp:/bad")
    #expect(model.comment == "hello")
    #expect(model.previewSummary != nil)
    #expect(model.canCreate)
    // Typing in a field clears that field's refusal only.
    model.trackersText = "udp://a.invalid"
    #expect(model.problem(.trackers) == nil)
    #expect(model.problem(.comment) == "Too long.")
  }

  @Test func aRefusalOfThePathShowsUnderWhatToShare() async {
    let (model, _, _) = await readyModel([
      "createTorrent": [CreateSample.refusal(["path": "There's nothing at /gone."])]
    ])
    await model.create()
    #expect(model.pathProblem == "There's nothing at /gone.")
    #expect(model.phase == .editing)
  }

  @Test func aRefusalWithNoFieldIsShownAsAGeneralFailure() async {
    let (model, _, _) = await readyModel([
      "createTorrent": [
        .error(.serviceUnavailable, code: "engine_down", message: "The engine is starting.")
      ]
    ])
    await model.create()
    #expect(model.generalFailure == "The engine is starting.")
    #expect(model.phase == .editing)
  }

  // MARK: Progress

  @Test func progressFollowsTheFeedsRecords() async {
    let (model, _, _) = await readyModel(["createTorrent": [CreateSample.created()]])
    await model.create()
    #expect(model.phase == .queued(behindAnother: false))
    #expect(model.progressLine == "Starting…")
    #expect(model.isMaking)
    #expect(model.fraction == nil)
    #expect(!model.isEditable)

    // A list that holds only another creation, before this one was ever listed, changes nothing.
    model.receive(creations: [CreateSample.record("other", state: .reading)])
    #expect(model.phase != .gone)
    // Another torrent is being read first.
    model.receive(creations: [
      CreateSample.record("other", state: .reading), CreateSample.record(state: .queued),
    ])
    #expect(model.phase == .queued(behindAnother: true))
    #expect(model.progressLine == "Waiting for the torrent before it to be made.")

    model.receive(creations: [CreateSample.record(state: .reading, read: 250, size: 1000)])
    #expect(model.phase == .reading(read: 250, size: 1000))
    #expect(model.fraction == 0.25)
    #expect(
      model.progressLine
        == "Reading every file to work out its pieces: 250 B of \(Format.bytes(1000)).")

  }

  @Test func doneAndSeedingSelectsTheNewTorrentOnce() async {
    let (model, _, selected) = await readyModel(["createTorrent": [CreateSample.created()]])
    await model.create()
    let done = CreateSample.record(state: .done, read: 1000, seeding: true, hash: CreateSample.hash)
    model.receive(creations: [done])
    model.receive(creations: [done])
    #expect(model.phase == .done)
    #expect(model.isSeeding)
    #expect(selected.hashes == [[CreateSample.hash]])
    #expect(model.madeSummary == "12 files, \(Format.bytes(1000)), 2,643 pieces of 16 MB")
    #expect(model.seedingProblem == nil)
  }

  @Test func doneWithoutSeedingSelectsNothing() async {
    let (model, _, selected) = await readyModel(["createTorrent": [CreateSample.created()]])
    model.startSeeding = false
    await model.create()
    model.receive(creations: [
      CreateSample.record(state: .done, read: 1000, seeding: false, hash: CreateSample.hash)
    ])
    #expect(model.phase == .done)
    #expect(!model.isSeeding)
    #expect(selected.hashes.isEmpty)
    #expect(model.seedingProblem == nil)
  }

  @Test func doneButCouldNotSeedSaysWhy() async {
    let (model, _, selected) = await readyModel(["createTorrent": [CreateSample.created()]])
    await model.create()
    model.receive(creations: [
      CreateSample.record(
        state: .done, read: 1000, seeding: false, error: "That torrent is already in the list.",
        hash: CreateSample.hash)
    ])
    #expect(model.phase == .done)
    #expect(model.seedingProblem == "That torrent is already in the list.")
    #expect(selected.hashes.isEmpty)
  }

  @Test func aFailedCreationShowsUmbrasReason() async {
    let (model, _, _) = await readyModel(["createTorrent": [CreateSample.created()]])
    await model.create()
    model.receive(creations: [
      CreateSample.record(state: .failed, error: "Couldn't read the files: permission denied.")
    ])
    #expect(model.phase == .failed("Couldn't read the files: permission denied."))
    #expect(!model.isMaking)
  }

  @Test func aCreationUmbraNoLongerListsIsGone() async {
    let (model, _, _) = await readyModel(["createTorrent": [CreateSample.created()]])
    await model.create()
    model.receive(creations: [CreateSample.record(state: .reading, read: 1, size: 1000)])
    model.receive(creations: [])
    #expect(model.phase == .gone)
  }

  @Test func tryAgainRemovesTheRecordAndReturnsToTheOptions() async throws {
    let (model, transport, _) = await readyModel(["createTorrent": [CreateSample.created()]])
    model.comment = "keep me"
    await model.create()
    model.receive(creations: [CreateSample.record(state: .failed, error: "No.")])
    await model.tryAgain()
    #expect(model.phase == .editing)
    #expect(model.comment == "keep me")
    #expect(model.canCreate)
    let removed = try #require(await transport.sent("removeCreation").first)
    #expect(removed.method == .delete)
    #expect(removed.path.hasSuffix("/creations/abc123"))
  }

  // MARK: Cancel and close

  @Test func cancelStopsTheCreationAtUmbra() async throws {
    let (model, transport, _) = await readyModel(["createTorrent": [CreateSample.created()]])
    await model.create()
    model.receive(creations: [CreateSample.record(state: .reading, read: 10)])
    await model.cancel()
    let removed = try #require(await transport.sent("removeCreation").first)
    #expect(removed.method == .delete)
    #expect(removed.path.hasSuffix("/creations/abc123"))
    // Closing afterwards does not send it twice.
    await model.close()
    #expect(await transport.count("removeCreation") == 1)
  }

  @Test func closingAfterItIsMadeDismissesTheRecord() async {
    let (model, transport, _) = await readyModel(["createTorrent": [CreateSample.created()]])
    await model.create()
    model.receive(creations: [
      CreateSample.record(state: .done, read: 1000, seeding: true, hash: CreateSample.hash)
    ])
    await model.close()
    await model.close()
    #expect(await transport.count("removeCreation") == 1)
  }

  @Test func closingWithNothingMadeSendsNothing() async {
    let (model, transport, _) = await readyModel()
    await model.close()
    #expect(await transport.count("removeCreation") == 0)
  }

  @Test func closingWhileUmbraIsStillAnsweringCleansUpWhenItAnswers() async {
    let (model, transport, _) = await readyModel(["createTorrent": [CreateSample.created()]])
    await transport.hold("createTorrent")
    let creating = Task { await model.create() }
    #expect(await eventually { await transport.count("createTorrent") == 1 })
    await model.close()
    await transport.release("createTorrent")
    await creating.value
    #expect(await transport.count("removeCreation") == 1)
  }

  @Test func closingTheSheetDropsAPreviewStillOnItsWay() async {
    let (model, transport, _) = model(["previewCreation": [CreateSample.preview]])
    await transport.hold("previewCreation")
    model.choose(url: URL(fileURLWithPath: CreateSample.folder))
    await model.close()
    await transport.release("previewCreation")
    try? await Task.sleep(for: .milliseconds(40))
    #expect(model.previewSummary == nil)
  }

  // MARK: Saving the .torrent file

  @Test func saveWritesUmbrasFile() async throws {
    let bytes = "d4:infod4:name4:testee"
    let (model, transport, _) = await readyModel([
      "createTorrent": [CreateSample.created()],
      "downloadCreation": [
        .init(status: .ok, contentType: "application/x-bittorrent", body: bytes)
      ],
    ])
    await model.create()
    model.receive(creations: [
      CreateSample.record(state: .done, read: 1000, seeding: true, hash: CreateSample.hash)
    ])
    #expect(model.suggestedFileName == "Holiday.Photos.torrent")
    let url = FileManager.default.temporaryDirectory.appending(
      path: "create-test-\(UUID().uuidString).torrent")
    defer { try? FileManager.default.removeItem(at: url) }
    await model.saveTorrentFile(to: url)
    #expect(try Data(contentsOf: url) == Data(bytes.utf8))
    #expect(model.saveFailure == nil)
    let asked = try #require(await transport.sent("downloadCreation").first)
    #expect(asked.path.hasSuffix("/creations/abc123/torrent"))
  }

  @Test func aFailedSaveSaysWhy() async {
    let (model, _, _) = await readyModel([
      "createTorrent": [CreateSample.created()],
      "downloadCreation": [
        .error(.conflict, code: "not_made", message: "The torrent isn't made yet.")
      ],
    ])
    await model.create()
    model.receive(creations: [CreateSample.record(state: .done, read: 1000)])
    await model.saveTorrentFile(
      to: FileManager.default.temporaryDirectory.appending(path: "x.torrent"))
    #expect(model.saveFailure == "The torrent isn't made yet.")
  }

  @Test func theSeedingNoteIsPlain() {
    #expect(
      CreateTorrentModel.seedingNote
        == "Umbra seeds the files from where they are. Moving or deleting them stops the torrent working."
    )
  }
}

/// Piece sizes by name, for the tests.
enum PieceSizeChoice {
  static func mb(_ n: Int64) -> CreateTorrentModel.PieceSize {
    .init(bytes: n << 20)
  }
}
