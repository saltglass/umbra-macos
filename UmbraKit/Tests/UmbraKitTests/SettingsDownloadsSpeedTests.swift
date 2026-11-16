import Foundation
import Testing
import UmbraAPI

@testable import UmbraKit

typealias DownloadsValue = Components.Schemas.DownloadsSettings
typealias SpeedValue = Components.Schemas.SpeedSettings

/// A pretend Umbra holding one settings group of any kind: it can refuse
/// the next change and change the group "elsewhere" (the web page, the
/// toolbar's tortoise, the schedule).
actor FakeGroupServer<Value: Equatable & Sendable> {
  var stored: Value
  private(set) var writes: [Value] = []
  private var refusals: [UmbraError] = []

  init(_ stored: Value) { self.stored = stored }

  func refuseNext(_ error: UmbraError) { refusals.append(error) }
  func changeElsewhere(_ value: Value) { stored = value }

  func read() -> Value { stored }

  func write(_ value: Value) throws(UmbraError) -> Value {
    writes.append(value)
    if !refusals.isEmpty { throw refusals.removeFirst() }
    stored = value
    return value
  }

  nonisolated func group(_ name: String) -> SettingsGroup<Value> {
    SettingsGroup(
      name: name,
      read: { _ async throws(UmbraError) in await self.read() },
      write: { value, _ async throws(UmbraError) in try await self.write(value) })
  }
}

func sampleDownloads() -> DownloadsValue {
  DownloadsValue(
    folder: "", defaultFolder: "/Users/alex/Downloads/Umbra", incompleteFolder: "",
    categories: [
      .init(name: "Movies", folder: "/Volumes/Media/Movies", ratio: 2),
      .init(name: "Music", folder: ""),
    ], lowSpaceWarningGB: 5, watchFolder: "")
}

func sampleSpeed() -> SpeedValue {
  SpeedValue(
    downloadLimitKBs: 0, uploadLimitKBs: 500, slowMode: false, slowDownloadKBs: 200,
    slowUploadKBs: 50,
    slowModeSchedule: .init(enabled: false, days: [1, 2, 3, 4, 5], from: "22:00", to: "07:00"))
}

/// A calendar with fixed English names and a fixed zone, so tests read the
/// same on every Mac.
var englishCalendar: Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.locale = Locale(identifier: "en_US_POSIX")
  calendar.timeZone = TimeZone(identifier: "UTC")!
  return calendar
}

// MARK: Pure helpers

@Suite struct DownloadsHelperTests {
  @Test func blankMeansZeroForAnOptionalNumber() {
    let format = SettingsFormat<Int?>.wholeNumber(blank: 0)
    #expect(format.text(nil) == "")
    #expect(format.text(0) == "")
    #expect(format.text(5) == "5")
    if case .value(let value) = format.read("") { #expect(value == 0) } else { Issue.record() }
    if case .value(let value) = format.read(" 12 ") { #expect(value == 12) } else { Issue.record() }
    if case .value(let value) = format.read("2.6") { #expect(value == 3) } else { Issue.record() }
    if case .unreadable = format.read("lots") {} else { Issue.record() }
  }

  @Test func speedsAreMegabytesOnScreenAndKilobytesInUmbra() {
    let us = SettingsFormat<Int>.megabytesPerSecond(locale: Locale(identifier: "en_US"))
    let german = SettingsFormat<Int>.megabytesPerSecond(locale: Locale(identifier: "de_DE"))
    #expect(us.text(0) == "")
    #expect(us.text(1024) == "1")
    #expect(us.text(1536) == "1.5")
    #expect(us.text(500) == "0.5")  // rounded to one decimal, as the web page does
    #expect(us.text(3) == "")  // rounds to 0: no limit, as on the web page
    #expect(us.text(1_048_576) == "1024")  // no thousands separator
    #expect(german.text(1536) == "1,5")  // the Mac's decimal separator
    func read(_ format: SettingsFormat<Int>, _ text: String) -> Int? {
      if case .value(let value) = format.read(text) { return value }
      return nil
    }
    #expect(read(us, "1.5") == 1536)
    #expect(read(us, "1,5") == 1536)  // either way of writing it
    #expect(read(german, "1.5") == 1536)
    #expect(read(us, " 2 ") == 2048)
    #expect(read(us, "0.3") == 307)  // 307.2, rounded
    #expect(read(us, "") == 0)
    #expect(read(us, "0") == 0)
    #expect(read(us, "fast") == nil)
    #expect(read(us, "1.2.3") == nil)
  }

  @Test func foldersShowTheHomeFolderAsATilde() {
    let home = "/Users/alex"
    #expect(FolderPath.abbreviated("/Users/alex", home: home) == "~")
    #expect(FolderPath.abbreviated("/Users/alex/Movies/New", home: home) == "~/Movies/New")
    #expect(
      FolderPath.abbreviated("/Users/alexandra/Movies", home: home) == "/Users/alexandra/Movies")
    #expect(FolderPath.abbreviated("/Volumes/Media", home: home) == "/Volumes/Media")
    #expect(FolderPath.abbreviated("/Users/alex/Movies", home: "/Users/alex/") == "~/Movies")
    #expect(FolderPath.abbreviated("/tmp", home: "/") == "/tmp")
    #expect(FolderPath.abbreviated("", home: home) == "")
  }

  @Test func addingACategoryTrimsWhatWasTyped() {
    var value = sampleDownloads()
    CategoryEdits.add(name: "  TV ", folder: " /Volumes/Media/TV\n", to: &value)
    #expect(value.categories.count == 3)
    #expect(value.categories[2] == .init(name: "TV", folder: "/Volumes/Media/TV"))
    // No folder is the download folder.
    CategoryEdits.add(name: "Books", folder: "", to: &value)
    #expect(value.categories[3].folder == "")
  }

  @Test func editingRenamesAndKeepsTheCategorysOtherSettings() {
    var value = sampleDownloads()
    CategoryEdits.edit("Movies", name: "Films", folder: "/Volumes/Media/Films", in: &value)
    #expect(value.categories[0].name == "Films")
    #expect(value.categories[0].folder == "/Volumes/Media/Films")
    #expect(value.categories[0].ratio == 2)  // set on the web page; untouched
    #expect(value.categories[1].name == "Music")
  }

  @Test func editingACategoryThatIsGoneDoesNothing() {
    var value = sampleDownloads()
    let before = value
    CategoryEdits.edit("Gone", name: "x", folder: "y", in: &value)
    #expect(value == before)
  }

  @Test func removingACategoryTakesOnlyThatOne() {
    var value = sampleDownloads()
    CategoryEdits.remove("Movies", from: &value)
    #expect(value.categories.map(\.name) == ["Music"])
    CategoryEdits.remove("Nope", from: &value)
    #expect(value.categories.count == 1)
  }

  @Test func theSheetKnowsWhenNothingChanged() {
    let movies = sampleDownloads().categories[0]
    #expect(CategoryEdits.isUnchanged(movies, name: "Movies ", folder: "/Volumes/Media/Movies"))
    #expect(!CategoryEdits.isUnchanged(movies, name: "Film", folder: "/Volumes/Media/Movies"))
    #expect(!CategoryEdits.isUnchanged(movies, name: "Movies", folder: ""))
    #expect(CategoryEdits.index(of: "Music", in: sampleDownloads()) == 1)
    #expect(CategoryEdits.index(of: "music", in: sampleDownloads()) == nil)
  }

  @Test func refusalsAreSortedForTheSheet() {
    let duplicate = UmbraError(
      code: "invalid", message: "Some fields need attention.",
      fields: ["categories.2.name": "There's already a category with this name."])
    let problems = CategoryProblems(duplicate, index: 2)
    #expect(problems.name == "There's already a category with this name.")
    #expect(problems.folder == nil && problems.general == nil)

    let folder = UmbraError(
      code: "invalid", message: "x", fields: ["categories.1.folder": "Can't use that folder."])
    #expect(CategoryProblems(folder, index: 1).folder == "Can't use that folder.")

    // Another category's problem, or the main folder's, is not this sheet's field.
    #expect(CategoryProblems(folder, index: 0).general == "Can't use that folder.")
    #expect(CategoryProblems(folder, index: 0).folder == nil)

    // No field named: Umbra's message.
    let broken = UmbraError(code: "internal", message: "Something went wrong.")
    #expect(CategoryProblems(broken, index: 0).general == "Something went wrong.")
    #expect(CategoryProblems(nil, index: 0).isEmpty)
  }
}

@Suite struct ScheduleHelperTests {
  @Test func clockTextAndTimesConvertBothWays() {
    let calendar = englishCalendar
    let day = Date(timeIntervalSince1970: 1_794_493_800)  // any day
    let date = ClockTime.date(from: "22:05", on: day, calendar: calendar)
    #expect(date != nil)
    #expect(date.map { ClockTime.text(from: $0, calendar: calendar) } == "22:05")
    #expect(ClockTime.text(hour: 7, minute: 0) == "07:00")
    #expect(ClockTime.date(from: "00:00", on: day, calendar: calendar) != nil)
  }

  @Test func textThatIsntATimeGivesNoDate() {
    for bad in ["", "7", "24:00", "12:60", "ab:cd", "1:2:3", ":30", "-1:00"] {
      #expect(ClockTime.parse(bad) == nil, "\(bad)")
    }
    #expect(ClockTime.parse("7:5")?.hour == 7)  // lenient about missing zeros
    #expect(ClockTime.date(from: "later", calendar: englishCalendar) == nil)
  }

  @Test func timesShowTheMacsWay() {
    let calendar = englishCalendar
    #expect(
      ClockTime.display("22:00", calendar: calendar, locale: Locale(identifier: "de_DE"))
        == "22:00")
    #expect(
      ClockTime.display("22:00", calendar: calendar, locale: Locale(identifier: "en_US"))
        .hasPrefix("10:00"))
    #expect(ClockTime.display("later", calendar: calendar) == "later")
  }

  @Test func daysAreAddedAndRemovedInOrder() {
    #expect(ScheduleDays.setting(0, on: true, in: [1, 3]) == [0, 1, 3])
    #expect(ScheduleDays.setting(3, on: false, in: [1, 3]) == [1])
    #expect(ScheduleDays.setting(1, on: true, in: [1, 3]) == [1, 3])
    #expect(ScheduleDays.setting(2, on: false, in: [1, 3]) == [1, 3])
    #expect(ScheduleDays.displayOrder.sorted() == Array(0...6))
  }

  @Test func dayNamesFollowUmbrasNumbers() {
    let calendar = englishCalendar
    #expect(ScheduleDays.name(of: 0, calendar: calendar) == "Sunday")
    #expect(ScheduleDays.name(of: 6, calendar: calendar) == "Saturday")
    #expect(ScheduleDays.shortName(of: 1, calendar: calendar) == "Mon")
  }

  @Test func daysAreWordedAsOnTheWebPage() {
    let calendar = englishCalendar
    func words(_ days: [Int]) -> String { ScheduleDays.words(days, calendar: calendar) }
    #expect(words([1, 2, 3, 4, 5, 6, 0]) == "every day")
    #expect(words([1, 2, 3, 4, 5]) == "Monday to Friday")
    #expect(words([6, 0]) == "Saturday and Sunday")
    #expect(words([1, 3, 5]) == "Monday, Wednesday and Friday")
    #expect(words([4]) == "Thursday")
    #expect(words([]) == "no days")
    #expect(words([5, 6, 0]) == "Friday to Sunday")  // the week starts on Monday
  }

  @Test func theSummarySaysWhenSlowModeRuns() {
    let calendar = englishCalendar
    let german24h = Locale(identifier: "de_DE")
    func summary(_ days: [Int], _ from: String, _ to: String) -> String {
      ScheduleSummary.text(days: days, from: from, to: to, calendar: calendar, locale: german24h)
    }
    #expect(
      summary([1, 2, 3, 4, 5], "10:00", "17:00")
        == "Slow mode runs Monday to Friday, 10:00 to 17:00. "
        + "At all other times Umbra uses the normal limits.")
    #expect(summary([], "10:00", "17:00") == "Choose at least one day.")
    // To earlier than from: past midnight, on the day it starts.
    let night = summary([5], "22:00", "10:00")
    #expect(night.contains("22:00 to 10:00 the next morning"))
    #expect(night.contains("past midnight"))
    #expect(summary([5], "08:00", "08:00").contains("all day"))
  }
}

// MARK: Changing and waiting

@MainActor @Suite struct DownloadsModelTests {
  func loaded(_ server: FakeGroupServer<DownloadsValue>) async -> SettingsGroupModel<
    DownloadsValue
  > {
    let model = SettingsGroupModel(server.group("downloads"), source: FakeSettingsSource())
    #expect(await eventually { model.phase == .loaded })
    return model
  }

  @Test func addingACategorySavesAndReturnsNoRefusal() async {
    let server = FakeGroupServer(sampleDownloads())
    let model = await loaded(server)
    let refusal = await model.changeAndWait {
      CategoryEdits.add(name: "TV", folder: "/Volumes/Media/TV", to: &$0)
    }
    #expect(refusal == nil)
    #expect(await server.stored.categories.map(\.name) == ["Movies", "Music", "TV"])
    #expect(model.value?.categories.count == 3)
  }

  @Test func aRefusedCategoryComesBackWithUmbrasWordsAndChangesNothing() async {
    let server = FakeGroupServer(sampleDownloads())
    let model = await loaded(server)
    let words = "There's already a category with this name."
    await server.refuseNext(
      UmbraError(
        code: "invalid", message: "Some fields need attention.",
        fields: ["categories.2.name": words]))
    let refusal = await model.changeAndWait {
      CategoryEdits.add(name: "movies", folder: "", to: &$0)
    }
    #expect(CategoryProblems(refusal, index: 2).name == words)
    #expect(model.value?.categories.count == 2)  // back to what Umbra has
    // The sheet stays open; a corrected name then goes through.
    let again = await model.changeAndWait {
      CategoryEdits.add(name: "Shows", folder: "", to: &$0)
    }
    #expect(again == nil)
    #expect(await server.stored.categories.map(\.name) == ["Movies", "Music", "Shows"])
  }

  @Test func removingACategorySendsTheListWithoutIt() async {
    let server = FakeGroupServer(sampleDownloads())
    let model = await loaded(server)
    let refusal = await model.changeAndWait { CategoryEdits.remove("Movies", from: &$0) }
    #expect(refusal == nil)
    #expect(await server.stored.categories.map(\.name) == ["Music"])
  }

  @Test func theLowSpaceBoxLeftEmptyIsSentAsZeroNotLeftOut() async {
    let server = FakeGroupServer(sampleDownloads())
    let model = await loaded(server)
    model.type("", into: \.lowSpaceWarningGB)
    model.commit(\.lowSpaceWarningGB, as: .wholeNumber(blank: 0))
    #expect(await eventually { await server.stored.lowSpaceWarningGB == 0 })
  }

  @Test func theFoldersAreSentAsEmptyTextToTurnThemOff() async {
    var start = sampleDownloads()
    start.watchFolder = "/Users/alex/Watch"
    start.incompleteFolder = "/Users/alex/Partial"
    let server = FakeGroupServer(start)
    let model = await loaded(server)
    model.set(\.watchFolder, to: "")
    model.set(\.incompleteFolder, to: "")
    #expect(await eventually { await server.stored.watchFolder == "" })
    #expect(await eventually { await server.stored.incompleteFolder == "" })
  }
}

@MainActor @Suite struct SpeedModelTests {
  @Test func theLimitsShowAsMegabytesAndZeroIsEmpty() async {
    let server = FakeGroupServer(sampleSpeed())
    let model = SettingsGroupModel(server.group("speed"), source: FakeSettingsSource())
    #expect(await eventually { model.phase == .loaded })
    let format = SettingsFormat<Int>.megabytesPerSecond(locale: Locale(identifier: "en_US"))
    #expect(model.text(\.downloadLimitKBs, as: format) == "")
    #expect(model.text(\.uploadLimitKBs, as: format) == "0.5")  // 500 KB/s
    model.type("1.5", into: \.downloadLimitKBs)
    model.commit(\.downloadLimitKBs, as: format)
    #expect(await eventually { await server.stored.downloadLimitKBs == 1536 })
    model.type("", into: \.uploadLimitKBs)
    model.commit(\.uploadLimitKBs, as: format)
    #expect(await eventually { await server.stored.uploadLimitKBs == 0 })
  }

  /// The toolbar's tortoise and the Speed page's slow-mode switch are one
  /// setting. The toolbar writes it straight to Umbra, which then announces
  /// that "speed" changed; the page's model hears that and reads it again.
  @Test func theToolbarsTortoiseMovesThePagesSwitch() async {
    let server = FakeGroupServer(sampleSpeed())
    let source = FakeSettingsSource()
    let model = SettingsGroupModel(server.group("speed"), source: source)
    #expect(await eventually { model.phase == .loaded })
    #expect(model.value?.slowMode == false)

    var tortoise = sampleSpeed()
    tortoise.slowMode = true
    await server.changeElsewhere(tortoise)
    source.store.announceSettingsChanged("speed")
    #expect(await eventually { model.value?.slowMode == true })

    // And the other way: the page's switch reaches Umbra at once.
    model.set(\.slowMode, to: false)
    #expect(await eventually { await server.stored.slowMode == false })
  }

  @Test func theScheduleIsChangedThroughTheGroup() async {
    let server = FakeGroupServer(sampleSpeed())
    let model = SettingsGroupModel(server.group("speed"), source: FakeSettingsSource())
    #expect(await eventually { model.phase == .loaded })
    model.set(\.slowModeSchedule.enabled, to: true)
    model.change {
      $0.slowModeSchedule.days = ScheduleDays.setting(6, on: true, in: $0.slowModeSchedule.days)
    }
    model.set(\.slowModeSchedule.from, to: ClockTime.text(hour: 23, minute: 30))
    #expect(await eventually { await server.stored.slowModeSchedule.from == "23:30" })
    let stored = await server.stored.slowModeSchedule
    #expect(stored.enabled && stored.days == [1, 2, 3, 4, 5, 6])
  }
}
