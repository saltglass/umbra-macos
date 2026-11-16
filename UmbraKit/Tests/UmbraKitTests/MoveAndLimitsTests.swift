import Foundation
import HTTPTypes
import Testing
import UmbraAPI

@testable import UmbraKit

private let connection = Connection(
  baseURL: URL(string: "http://127.0.0.1:7980")!, credential: .apiKey("key"))
private let english = Locale(identifier: "en_US")
private let hashes = ["aaa", "bbb"]

private func actions(_ replies: [String: RecordingTransport.Reply] = [:]) -> (
  TorrentActions, RecordingTransport
) {
  let transport = RecordingTransport(replies)
  return (TorrentActions(connection: connection, transport: transport), transport)
}

/// What Umbra answers for one torrent's limits: its own, the ones in force, its category.
private let limitsJSON = """
  {"own":{"ratio":null,"seedingMinutes":90,"inactiveMinutes":-1,\
  "downloadLimitKBs":0,"uploadLimitKBs":1536},\
  "inForce":{"ratio":2,"seedingMinutes":90,"inactiveMinutes":null,\
  "downloadLimitKBs":0,"uploadLimitKBs":1536,\
  "from":{"ratio":"global","seedingMinutes":"torrent","inactiveMinutes":"torrent",\
  "downloadLimitKBs":"none","uploadLimitKBs":"torrent"}},\
  "category":"films"}
  """
private let seedingJSON = #"{"ratio":2,"seedingMinutes":null,"inactiveMinutes":600}"#
private let downloadsJSON = """
  {"folder":"","incompleteFolder":"","categories":[\
  {"name":"films","folder":"","ratio":1.5,"downloadLimitKBs":2048,"uploadLimitKBs":0}]}
  """
private let refusedJSON = """
  {"code":"invalid","message":"Some fields need attention.",\
  "fields":{"ratio":"A ratio can't be more than 1000.","uploadLimitKBs":"Enter 0 or more."}}
  """

// MARK: Moving

@Suite("moving torrents' files") struct MoveTests {
  @Test func oneTorrentPostsTheFolder() async throws {
    let (actions, transport) = actions()
    try await actions.move(["aaa"], to: "/Volumes/Media/Films")
    let sent = try #require(await transport.sent.first)
    #expect(sent.operation == "moveTorrents")
    #expect(sent.method == .post)
    #expect(sent.path == "/torrents/move")
    #expect(sent.json == ["hashes": ["aaa"], "folder": "/Volumes/Media/Films"])
  }

  @Test func manyTorrentsGoInOneRequest() async throws {
    let (actions, transport) = actions()
    try await actions.move(hashes, to: "/Volumes/Media/Films")
    #expect(await transport.sent.count == 1)
    #expect(
      await transport.sent.first?.json == ["hashes": hashes, "folder": "/Volumes/Media/Films"])
  }

  @Test func noTorrentsSendNothing() async throws {
    let (actions, transport) = actions()
    try await actions.move([], to: "/x")
    #expect(await transport.sent.isEmpty)
  }

  @Test func aRefusalCarriesUmbrasWords() async {
    let (actions, _) = actions([
      "moveTorrents": .error(.conflict, code: "busy", message: "“Alpha” is being moved already.")
    ])
    await #expect(throws: UmbraError.self) { try await actions.move(hashes, to: "/x") }
    do {
      try await actions.move(hashes, to: "/x")
    } catch {
      #expect(error.message == "“Alpha” is being moved already.")
    }
  }

  @MainActor @Test func theWindowShowsARefusalInTheAlert() async throws {
    let (model, _) = makeModel(defaults: throwawayDefaults())
    let transport = RecordingTransport([
      "moveTorrents": .error(
        .unprocessableContent, code: "invalid", message: "That folder isn't writable.")
    ])
    let actions = TorrentActions(connection: connection, transport: transport)
    await model.move(["a1", "b2"], to: "/nope", using: actions)
    #expect(model.actionFailure?.title == "Couldn't move the files of 2 torrents")
    #expect(model.actionFailure?.message == "That folder isn't writable.")
    await model.move(["a1"], to: "/ok", using: nil)  // not connected: nothing happens
    #expect(await transport.sent.count == 1)
  }

  @MainActor @Test func theChooserStartsAtTheFirstSelectedTorrentsFolder() {
    let (model, _) = makeModel(
      [
        torrent("a1", name: "Alpha") { $0.savePath = "/Volumes/Media/A" },
        torrent("b2", name: "Bravo") { $0.savePath = "/Volumes/Media/B" },
      ], defaults: throwawayDefaults())
    model.selection = ["a1", "b2"]
    // The newest is first in the list, which is Bravo (same added time: either is a row).
    #expect(["/Volumes/Media/A", "/Volumes/Media/B"].contains(model.firstSaveFolder))
    model.selection = []
    #expect(model.firstSaveFolder == "")
  }
}

// MARK: A torrent's own limits: the requests

@Suite("a torrent's own limits, as sent") struct LimitsRequestTests {
  @Test func readsOneTorrentsLimits() async throws {
    let (actions, transport) = actions(["getTorrentLimits": .json(limitsJSON)])
    let limits = try await actions.limits(of: "aaa")
    #expect(limits.own.seedingMinutes == 90)
    #expect(limits.category == "films")
    let sent = try #require(await transport.sent.first)
    #expect(sent.method == .get && sent.path == "/torrents/aaa/limits")
  }

  @Test func settingValuesSendsOnlyThoseFields() async throws {
    let (actions, transport) = actions()
    var changes = TorrentLimitChanges()
    changes.uploadLimitKBs = .set(1536)
    changes.ratio = .set(2.5)
    try await actions.setLimits(changes, for: ["aaa"])
    let sent = try #require(await transport.sent.first)
    #expect(sent.operation == "setTorrentsLimits")
    #expect(sent.method == .put && sent.path == "/torrents/limits")
    #expect(sent.json == ["hashes": ["aaa"], "uploadLimitKBs": 1536, "ratio": 2.5])
  }

  @Test func clearingSendsNullForGoalsAndZeroForSpeeds() async throws {
    let (actions, transport) = actions()
    var changes = TorrentLimitChanges()
    changes.ratio = .useDefault
    changes.seedingMinutes = .useDefault
    changes.inactiveMinutes = .useDefault
    changes.downloadLimitKBs = .useDefault
    changes.uploadLimitKBs = .useDefault
    try await actions.setLimits(changes, for: ["aaa"])
    let json = try #require(await transport.sent.first?.json)
    #expect(
      json == [
        "hashes": ["aaa"], "ratio": NSNull(), "seedingMinutes": NSNull(),
        "inactiveMinutes": NSNull(), "downloadLimitKBs": 0, "uploadLimitKBs": 0,
      ])
  }

  @Test func noGoalSendsANegativeNumber() async throws {
    let (actions, transport) = actions()
    var changes = TorrentLimitChanges()
    changes.ratio = .noGoal
    changes.inactiveMinutes = .noGoal
    try await actions.setLimits(changes, for: ["aaa"])
    let json = try #require(await transport.sent.first?.json)
    #expect(json == ["hashes": ["aaa"], "ratio": -1, "inactiveMinutes": -1])
  }

  @Test func severalTorrentsGoInOneRequestAndKeepTheRest() async throws {
    let (actions, transport) = actions()
    var changes = TorrentLimitChanges()
    changes.downloadLimitKBs = .set(512)
    try await actions.setLimits(changes, for: hashes)
    #expect(await transport.sent.count == 1)
    #expect(await transport.sent.first?.json == ["hashes": hashes, "downloadLimitKBs": 512])
  }

  @Test func nothingIsSentWhenNothingChangesOrNoTorrents() async throws {
    let (actions, transport) = actions()
    try await actions.setLimits(TorrentLimitChanges(), for: hashes)
    var changes = TorrentLimitChanges()
    changes.ratio = .set(1)
    try await actions.setLimits(changes, for: [])
    #expect(await transport.sent.isEmpty)
  }

  @Test func aRefusalCarriesUmbrasWordsAndFields() async {
    let (actions, _) = actions([
      "setTorrentsLimits": .json(refusedJSON, status: .unprocessableContent)
    ])
    var changes = TorrentLimitChanges()
    changes.ratio = .set(5000)
    do {
      try await actions.setLimits(changes, for: ["aaa"])
      Issue.record("Umbra's refusal should throw")
    } catch {
      #expect(error.fields["ratio"] == "A ratio can't be more than 1000.")
    }
  }
}

// MARK: The draft (what the boxes hold)

@Suite("the limits draft") struct LimitsDraftTests {
  func own(
    ratio: Double? = nil, seeding: Int? = nil, inactive: Int? = nil, down: Int = 0, up: Int = 0
  ) -> Components.Schemas.OwnLimits {
    .init(
      ratio: ratio, seedingMinutes: seeding, inactiveMinutes: inactive, downloadLimitKBs: down,
      uploadLimitKBs: up)
  }

  @Test func oneTorrentStartsWithItsStoredValuesInTheSettingsUnits() {
    let draft = LimitsDraft(
      own: own(ratio: 2, seeding: 90, inactive: 45, down: 0, up: 1536), locale: english)
    #expect(draft[.downloadLimit].text == "")
    #expect(draft[.uploadLimit].text == "1.5")
    #expect(draft[.ratio].text == "2")
    #expect(draft[.seedingTime].text == "1.5")
    #expect(draft[.inactiveTime].text == "45")
    #expect(!draft.isEdited)
  }

  @Test func aNegativeStoredGoalIsNoGoal() {
    let draft = LimitsDraft(own: own(ratio: -1, seeding: -5), locale: english)
    #expect(draft[.ratio].mode == .noGoal)
    #expect(draft[.seedingTime].mode == .noGoal)
    #expect(draft[.inactiveTime].mode == .own)
  }

  @Test func nothingTouchedSendsNothingEvenWhenValuesAreRoundedForShowing() {
    // 1000 KB/s shows as "1" MB/s; pressing Save must not turn it into 1024.
    let draft = LimitsDraft(own: own(up: 1000), locale: english)
    #expect(draft[.uploadLimit].text == "1")
    #expect(draft.torrentChanges()?.isEmpty == true)
  }

  @Test func typedValuesAreReadAsMegabytesAndHours() throws {
    var draft = LimitsDraft(own: own(), locale: english)
    draft.type("2.5", into: .downloadLimit)
    draft.type("1,5", into: .ratio)
    draft.type("2", into: .seedingTime)
    draft.type("30", into: .inactiveTime)
    let changes = try #require(draft.torrentChanges())
    #expect(changes.downloadLimitKBs == .set(2560))
    #expect(changes.uploadLimitKBs == .keep)
    #expect(changes.ratio == .set(1.5))
    #expect(changes.seedingMinutes == .set(120))
    #expect(changes.inactiveMinutes == .set(30))
  }

  @Test func oneTorrentABlankedBoxClearsItAndTheOthersStay() throws {
    var draft = LimitsDraft(own: own(ratio: 2, up: 1024), locale: english)
    draft.type("", into: .uploadLimit)
    draft.type("", into: .ratio)
    let changes = try #require(draft.torrentChanges())
    #expect(changes.uploadLimitKBs == .useDefault)
    #expect(changes.ratio == .useDefault)
    #expect(changes.seedingMinutes == .keep)
  }

  @Test func zeroAndBlankMeanTheSameForASpeed() throws {
    var draft = LimitsDraft(own: own(up: 1024), locale: english)
    draft.type("0", into: .uploadLimit)
    #expect(draft.torrentChanges()?.uploadLimitKBs == .useDefault)
    draft.type("", into: .uploadLimit)
    #expect(draft.torrentChanges()?.uploadLimitKBs == .useDefault)
  }

  @Test func zeroIsARealRatioGoalNotBlank() throws {
    var draft = LimitsDraft(own: own(), locale: english)
    draft.type("0", into: .ratio)
    #expect(draft.torrentChanges()?.ratio == .set(0))
  }

  @Test func noGoalIsChosenFromTheMenu() {
    var draft = LimitsDraft(own: own(ratio: 2), locale: english)
    draft.choose(.noGoal, for: .ratio)
    #expect(draft.torrentChanges()?.ratio == .noGoal)
    draft.choose(.useDefault, for: .ratio)
    #expect(draft.torrentChanges()?.ratio == .useDefault)
  }

  @Test func severalStartBlankAndABlankBoxLeavesTheLimitAlone() {
    var draft = LimitsDraft(several: true, locale: english)
    #expect(draft.torrentChanges()?.isEmpty == true)
    draft.type("3", into: .uploadLimit)
    #expect(draft.torrentChanges()?.uploadLimitKBs == .set(3072))
    // Emptying the box again is "leave it", not "clear it".
    draft.type("", into: .uploadLimit)
    #expect(draft.torrentChanges()?.isEmpty == true)
  }

  @Test func severalCanClearOrLeaveFromTheMenu() {
    var draft = LimitsDraft(several: true, locale: english)
    draft.choose(.useDefault, for: .downloadLimit)
    draft.choose(.noGoal, for: .inactiveTime)
    #expect(draft.torrentChanges()?.downloadLimitKBs == .useDefault)
    #expect(draft.torrentChanges()?.inactiveMinutes == .noGoal)
    draft.choose(.leave, for: .downloadLimit)
    #expect(draft.torrentChanges()?.downloadLimitKBs == .keep)
  }

  @Test func halfTypedTextIsNeverSent() {
    var draft = LimitsDraft(own: own(), locale: english)
    draft.type("1.2.3", into: .ratio)
    draft.type("abc", into: .uploadLimit)
    #expect(draft.torrentChanges() == nil)
    #expect(Set(draft.problems.keys) == [.ratio, .uploadLimit])
    draft.type("1.2", into: .ratio)
    draft.type("", into: .uploadLimit)
    #expect(draft.torrentChanges() != nil)
  }
}

// MARK: Categories

@Suite("a category's limits") struct CategoryLimitsTests {
  func category(
    ratio: Double? = nil, seeding: Int? = nil, inactive: Int? = nil, down: Int? = nil,
    up: Int? = nil
  ) -> Components.Schemas.Category {
    .init(
      name: "Films", folder: "/Media/Films", ratio: ratio, seedingMinutes: seeding,
      inactiveMinutes: inactive, downloadLimitKBs: down, uploadLimitKBs: up)
  }

  @Test func theSheetStartsWithTheStoredValues() {
    let draft = LimitsDraft(
      category: CategoryLimits(category(ratio: 2, seeding: 120, down: 2048)), locale: english)
    #expect(draft[.ratio].text == "2")
    #expect(draft[.seedingTime].text == "2")
    #expect(draft[.downloadLimit].text == "2")
    #expect(draft[.uploadLimit].text == "")
    #expect(draft[.inactiveTime].text == "")
  }

  @Test func changesRoundTripIntoTheCategory() throws {
    let original = category(ratio: 2, down: 2048)
    var draft = LimitsDraft(category: CategoryLimits(original), locale: english)
    draft.type("3", into: .ratio)  // changed
    draft.type("1", into: .uploadLimit)  // new
    draft.type("", into: .downloadLimit)  // cleared
    draft.choose(.noGoal, for: .inactiveTime)
    let limits = try #require(draft.categoryLimits(base: CategoryLimits(original)))
    var value = Components.Schemas.DownloadsSettings(
      folder: "", incompleteFolder: "", categories: [original])
    CategoryEdits.edit("Films", name: "Films", folder: "/Media/Films", limits: limits, in: &value)
    let saved = value.categories[0]
    #expect(saved.ratio == 3)
    #expect(saved.uploadLimitKBs == 1024)
    #expect(saved.downloadLimitKBs == nil)
    #expect(saved.inactiveMinutes == -1)
    #expect(saved.seedingMinutes == nil)
  }

  @Test func blankGoalFollowsTheGlobalSettingAndANegativeOneIsNone() throws {
    var draft = LimitsDraft(category: CategoryLimits(category(ratio: 2)), locale: english)
    draft.type("", into: .ratio)
    #expect(
      try #require(draft.categoryLimits(base: CategoryLimits(category(ratio: 2)))).ratio == nil)
    draft.choose(.noGoal, for: .ratio)
    #expect(
      try #require(draft.categoryLimits(base: CategoryLimits(category(ratio: 2)))).ratio == -1)
  }

  @Test func zeroAndBlankSpeedsAreBothNone() throws {
    let base = CategoryLimits(category(up: 1024))
    var draft = LimitsDraft(category: base, locale: english)
    draft.type("0", into: .uploadLimit)
    #expect(try #require(draft.categoryLimits(base: base)).uploadLimitKBs == nil)
  }

  @Test func untouchedFieldsKeepWhatTheyWere() throws {
    let base = CategoryLimits(category(ratio: 2, up: 1000))  // 1000 shows as "1"
    let draft = LimitsDraft(category: base, locale: english)
    #expect(draft.categoryLimits(base: base) == base)
  }

  @Test func halfTypedTextIsNeverSavedInACategory() {
    let base = CategoryLimits(category())
    var draft = LimitsDraft(category: base, locale: english)
    draft.type("two", into: .ratio)
    #expect(draft.categoryLimits(base: base) == nil)
  }

  @Test func addingACategoryWithLimits() {
    var value = Components.Schemas.DownloadsSettings(
      folder: "", incompleteFolder: "", categories: [])
    CategoryEdits.add(
      name: " Music ", folder: "", limits: CategoryLimits(ratio: 1, downloadLimitKBs: 512),
      to: &value)
    #expect(value.categories.map(\.name) == ["Music"])
    #expect(value.categories[0].ratio == 1)
    #expect(value.categories[0].downloadLimitKBs == 512)
  }

  @Test func editingWithoutLimitsKeepsTheOnesItHad() {
    var value = Components.Schemas.DownloadsSettings(
      folder: "", incompleteFolder: "", categories: [category(ratio: 2, down: 100)])
    CategoryEdits.edit("Films", name: "Movies", folder: "", in: &value)
    #expect(value.categories[0].ratio == 2 && value.categories[0].downloadLimitKBs == 100)
  }

  @Test func changedLimitsCountAsAChange() {
    let original = category(ratio: 2)
    #expect(CategoryEdits.isUnchanged(original, name: "Films", folder: "/Media/Films"))
    #expect(
      CategoryEdits.isUnchanged(
        original, name: "Films", folder: "/Media/Films", limits: CategoryLimits(original)))
    #expect(
      !CategoryEdits.isUnchanged(
        original, name: "Films", folder: "/Media/Films", limits: CategoryLimits(ratio: 3)))
  }

  @Test func refusalsAreSortedUnderTheLimitBoxes() {
    let problems = CategoryProblems(
      UmbraError(
        code: "invalid", message: "Some fields need attention.",
        fields: [
          "categories.1.ratio": "Too big.", "categories.1.name": "Taken.",
          "categories.0.ratio": "Not mine.",
        ]), index: 1)
    #expect(problems.limits == [.ratio: "Too big."])
    #expect(problems.name == "Taken.")
    #expect(problems.general == "Not mine.")
    #expect(!problems.isEmpty)
  }
}

// MARK: Hints and the inspector's rows

@Suite("what applies when a box is blank") struct LimitHintsTests {
  let global = Components.Schemas.SeedingSettings(
    ratio: 2, seedingMinutes: nil, inactiveMinutes: 600)
  let films = Components.Schemas.Category(
    name: "films", folder: "", ratio: 1.5, downloadLimitKBs: 2048)

  @Test func aCategorysOwnGoalComesBeforeTheGlobalOne() {
    let hints = LimitHints(global: global, category: films, locale: english)
    let draft = LimitsDraft(
      own: .init(
        ratio: nil, seedingMinutes: nil, inactiveMinutes: nil, downloadLimitKBs: 0,
        uploadLimitKBs: 0), locale: english)
    #expect(hints.placeholder(for: .ratio, in: draft) == "Category: 1.5")
    #expect(hints.placeholder(for: .seedingTime, in: draft) == "No goal")
    #expect(hints.placeholder(for: .inactiveTime, in: draft) == "Global: 600 min")
    #expect(hints.placeholder(for: .downloadLimit, in: draft) == "Category: 2 MB/s")
    #expect(hints.placeholder(for: .uploadLimit, in: draft) == "No limit")
  }

  @Test func withoutACategoryTheGlobalGoalShows() {
    let hints = LimitHints(global: global, locale: english)
    let draft = LimitsDraft(locale: english)
    #expect(hints.placeholder(for: .ratio, in: draft) == "Global: 2")
  }

  @Test func whatIsNotKnownIsNotGuessed() {
    let unknown = LimitHints(locale: english)
    #expect(
      unknown.placeholder(for: .ratio, in: LimitsDraft(locale: english))
        == "Category's or global goal")
    let mixed = LimitHints(global: global, mixedCategories: true, locale: english)
    #expect(
      mixed.placeholder(for: .ratio, in: LimitsDraft(locale: english))
        == "Category's or global goal")
  }

  @Test func severalSayLeaveUntilTouchedThenWhatApplies() {
    let hints = LimitHints(global: global, locale: english)
    var draft = LimitsDraft(several: true, locale: english)
    #expect(hints.placeholder(for: .ratio, in: draft) == "Leave as it is")
    draft.choose(.useDefault, for: .ratio)
    #expect(hints.placeholder(for: .ratio, in: draft) == "Global: 2")
    draft.choose(.noGoal, for: .ratio)
    #expect(hints.placeholder(for: .ratio, in: draft) == "None for this torrent")
  }

  @Test func theInspectorListsOnlyWhatTheTorrentHasOfItsOwn() {
    let summary = LimitsSummary(
      .init(
        ratio: 2, seedingMinutes: 90, inactiveMinutes: -1, downloadLimitKBs: 0, uploadLimitKBs: 1536
      ),
      locale: english)
    #expect(
      summary.rows.map { [$0.title, $0.value] } == [
        ["Upload limit", "1.5 MB/s"], ["Seed ratio goal", "2"],
        ["Seeding time goal", "1.5 hours"], ["Inactive goal", "None"],
      ])
    let none = LimitsSummary(
      .init(
        ratio: nil, seedingMinutes: nil, inactiveMinutes: nil, downloadLimitKBs: 0,
        uploadLimitKBs: 0),
      locale: english)
    #expect(none.isEmpty)
  }
}

// MARK: The sheet's model

@MainActor @Suite("the Limits sheet's model") struct TorrentLimitsModelTests {
  func model(
    _ replies: [String: RecordingTransport.Reply], hashes: [String] = ["aaa"],
    categories: [String] = ["films"]
  ) -> (TorrentLimitsModel, RecordingTransport) {
    let transport = RecordingTransport(replies)
    let actions = TorrentActions(connection: connection, transport: transport)
    let request = LimitsRequest(hashes: hashes, name: "Alpha", categories: categories)
    return (
      TorrentLimitsModel(request: request, actions: { actions }, locale: english), transport
    )
  }

  static let loaded: [String: RecordingTransport.Reply] = [
    "getTorrentLimits": .json(limitsJSON), "getSeedingSettings": .json(seedingJSON),
    "getDownloadsSettings": .json(downloadsJSON),
  ]

  @Test func oneTorrentLoadsItsOwnLimitsAndTheHints() async {
    let (model, transport) = model(Self.loaded)
    await model.load()
    #expect(model.phase == .ready)
    #expect(model.draft[.uploadLimit].text == "1.5")
    #expect(model.draft[.seedingTime].text == "1.5")
    #expect(model.draft[.inactiveTime].mode == .noGoal)
    #expect(model.placeholder(for: .ratio) == "Category: 1.5")
    #expect(model.subheading == "Alpha")
    #expect(model.note == nil)
    #expect(await transport.sent.map(\.operation).first == "getTorrentLimits")
  }

  @Test func severalDoNotReadOneTorrentsLimitsAndSayWhatSaveDoes() async {
    let (model, transport) = model(
      Self.loaded, hashes: ["aaa", "bbb", "ccc"], categories: ["films", "films", "films"])
    await model.load()
    #expect(model.phase == .ready)
    #expect(!(await transport.sent.map(\.operation).contains("getTorrentLimits")))
    #expect(model.subheading == "3 torrents")
    #expect(model.note == "Changes apply to all 3 torrents; blank fields are left as they are.")
    #expect(model.placeholder(for: .ratio) == "Leave as it is")
  }

  @Test func aFailureToReadIsShownWithUmbrasWords() async {
    let (model, _) = model([
      "getTorrentLimits": .error(.notFound, code: "not_found", message: "That torrent is gone.")
    ])
    await model.load()
    #expect(model.phase == .loadFailed("That torrent is gone."))
    #expect(!model.canSave)
  }

  @Test func theHintsAreOptionalSoAFailureThereStillOpensTheSheet() async {
    let (model, _) = model([
      "getTorrentLimits": .json(limitsJSON),
      "getSeedingSettings": .error(.badGateway, code: "x", message: "No."),
    ])
    await model.load()
    #expect(model.phase == .ready)
  }

  @Test func saveSendsOnlyWhatWasChanged() async {
    let (model, transport) = model(Self.loaded)
    await model.load()
    model.type("3", into: .uploadLimit)
    let saved = await model.save()
    #expect(saved)
    let sent = await transport.sent.last
    #expect(sent?.operation == "setTorrentsLimits")
    #expect(sent?.json == ["hashes": ["aaa"], "uploadLimitKBs": 3072])
  }

  @Test func savingWithNothingChangedSendsNothingAndCloses() async {
    let (model, transport) = model(Self.loaded)
    await model.load()
    let before = await transport.sent.count
    #expect(await model.save())
    #expect(await transport.sent.count == before)
  }

  @Test func halfTypedTextBlocksSaveAndSendsNothing() async {
    let (model, transport) = model(Self.loaded)
    await model.load()
    let before = await transport.sent.count
    model.type("1.2.3", into: .ratio)
    #expect(!model.canSave)
    #expect(model.problem(for: .ratio) == "Enter a number.")
    #expect(!(await model.save()))
    #expect(await transport.sent.count == before)
  }

  @Test func aRefusalStaysInTheSheetUnderTheRightBoxes() async {
    var replies = Self.loaded
    replies["setTorrentsLimits"] = .json(refusedJSON, status: .unprocessableContent)
    let (model, _) = model(replies)
    await model.load()
    model.type("5000", into: .ratio)
    #expect(!(await model.save()))
    #expect(model.problem(for: .ratio) == "A ratio can't be more than 1000.")
    #expect(model.problem(for: .uploadLimit) == "Enter 0 or more.")
    #expect(model.generalProblem == nil)
    // Typing in a box takes its old complaint away.
    model.type("5", into: .ratio)
    #expect(model.problem(for: .ratio) == nil)
  }

  @Test func aRefusalWithNoFieldShowsAsAGeneralLine() async {
    var replies = Self.loaded
    replies["setTorrentsLimits"] = .error(
      .notFound, code: "not_found", message: "One of them is gone.")
    let (model, _) = model(replies)
    await model.load()
    model.type("5", into: .ratio)
    #expect(!(await model.save()))
    #expect(model.generalProblem == "One of them is gone.")
  }
}

// MARK: The menu

@MainActor @Suite("the new menu items") struct MoveAndLimitsMenuTests {
  func menu(selected: Set<String>, connected: Bool = true) -> TorrentMenu {
    let (model, _) = makeModel(defaults: throwawayDefaults())
    model.selection = selected
    return model.torrentMenu(connected: connected)
  }

  @Test func theyComeBeforeQueueWithTheirCommands() {
    let titles = menu(selected: ["a1"]).entries.compactMap { entry -> String? in
      if case .item(let item) = entry { return item.title }
      if case .submenu(let title, _, _, _) = entry { return title }
      return nil
    }
    let move = titles.firstIndex(of: "Move Data To…")
    let limits = titles.firstIndex(of: "Limits…")
    let queue = titles.firstIndex(of: "Queue")
    #expect(move != nil && limits != nil && queue != nil)
    #expect(move! > titles.firstIndex(of: "Copy Info Hash")!)
    #expect(limits! < queue!)
    #expect(menu(selected: ["a1"]).item("Move Data To…")?.command == .moveData)
    #expect(menu(selected: ["a1"]).item("Limits…")?.command == .editLimits)
  }

  @Test func theyWorkForOneOrManyTorrents() {
    for selected: Set<String> in [["a1"], ["a1", "b2", "c3"]] {
      #expect(menu(selected: selected).item("Move Data To…")?.enabled == true)
      #expect(menu(selected: selected).item("Limits…")?.enabled == true)
    }
  }

  @Test func theyAreDimmedWithNothingSelectedOrNotConnected() {
    #expect(menu(selected: []).item("Move Data To…")?.enabled == false)
    #expect(menu(selected: []).item("Limits…")?.enabled == false)
    #expect(menu(selected: ["a1"], connected: false).item("Move Data To…")?.enabled == false)
    #expect(menu(selected: ["a1"], connected: false).item("Limits…")?.enabled == false)
  }

  @Test func showLimitsOpensTheSheetForTheSelection() {
    let (model, _) = makeModel(defaults: throwawayDefaults())
    model.showLimits()
    #expect(model.limitsRequest == nil)  // nothing selected
    model.selection = ["a1", "d4"]
    model.showLimits()
    #expect(Set(model.limitsRequest?.hashes ?? []) == ["a1", "d4"])
    #expect(model.limitsSaves == 0)
    model.limitsSaved()
    #expect(model.limitsSaves == 1)
  }
}
