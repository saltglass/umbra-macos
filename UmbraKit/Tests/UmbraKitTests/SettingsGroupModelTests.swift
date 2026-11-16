import Foundation
import Testing
import UmbraAPI

@testable import UmbraKit

// MARK: Stand-ins

/// A stand-in for `AppSession`: a connection that tests switch on and off,
/// and a store whose settings-change notices tests send by hand.
@MainActor @Observable
final class FakeSettingsSource: SettingsSource {
  var settingsActions: SettingsActions?
  let store = TorrentStore()

  init(connected: Bool = true) {
    if connected { connect() }
  }

  /// A new connection. Its requests are never made: the test groups below
  /// answer from a `FakeSettingsServer` instead.
  func connect() {
    settingsActions = SettingsActions(
      connection: Connection(
        baseURL: URL(string: "http://127.0.0.1:1")!, credential: .apiKey("unused")),
      transport: RecordingTransport())
  }

  func listenForSettingsChanges(
    _ listener: @escaping @MainActor (String) -> Void
  ) -> SettingsSubscription {
    store.listenForSettingsChanges(listener)
  }
}

typealias Queue = Components.Schemas.QueueSettings

/// A pretend Umbra holding one Queue group. Tests can hold its answers to
/// see what the model does meanwhile, make it refuse, and change the
/// group "elsewhere" (as the web page would).
actor FakeSettingsServer {
  var stored: Queue
  private(set) var reads = 0
  private(set) var writes: [Queue] = []
  /// The most requests that were ever being answered at the same time.
  private(set) var mostAtOnce = 0
  private var active = 0
  private var holding = false
  private var held: [CheckedContinuation<Void, Never>] = []
  private var refusals: [UmbraError] = []
  private var readFailures: [UmbraError] = []

  init(_ stored: Queue = Queue(maxActiveDownloads: 3, maxActiveSeeds: 25)) {
    self.stored = stored
  }

  func hold() { holding = true }
  func release() {
    holding = false
    for waiter in held { waiter.resume() }
    held = []
  }
  var waiting: Int { held.count }
  func refuseNext(_ error: UmbraError) { refusals.append(error) }
  func failNextRead(_ error: UmbraError) { readFailures.append(error) }
  func changeElsewhere(_ value: Queue) { stored = value }

  func read() async throws(UmbraError) -> Queue {
    reads += 1
    try await answer { () throws(UmbraError) in
      if !readFailures.isEmpty { throw readFailures.removeFirst() }
    }
    return stored
  }

  func write(_ value: Queue) async throws(UmbraError) -> Queue {
    writes.append(value)
    try await answer { () throws(UmbraError) in
      if !refusals.isEmpty { throw refusals.removeFirst() }
    }
    stored = value
    return value
  }

  private func answer(_ check: () throws(UmbraError) -> Void) async throws(UmbraError) {
    active += 1
    mostAtOnce = max(mostAtOnce, active)
    if holding { await withCheckedContinuation { held.append($0) } }
    active -= 1
    try check()
  }

  /// The group, answered from this pretend server.
  nonisolated var group: SettingsGroup<Queue> {
    SettingsGroup(
      name: "queue",
      read: { _ async throws(UmbraError) in try await self.read() },
      write: { value, _ async throws(UmbraError) in try await self.write(value) })
  }
}

let refusedDownloads = UmbraError(
  code: "invalid", message: "Some fields need attention.",
  fields: ["maxActiveDownloads": "Enter a number from 1 to 50."])

// MARK: Tests

/// How a settings page's model behaves: loading, sending, refusals, one
/// request at a time, and following changes made elsewhere.
@MainActor @Suite struct SettingsGroupModelTests {
  /// A model on a fake server, loaded.
  func loaded(_ server: FakeSettingsServer = FakeSettingsServer()) async -> (
    SettingsGroupModel<Queue>, FakeSettingsSource, FakeSettingsServer
  ) {
    let source = FakeSettingsSource()
    let model = SettingsGroupModel(server.group, source: source)
    #expect(await eventually { model.phase == .loaded })
    return (model, source, server)
  }

  // MARK: States

  @Test func notConnectedThenLoadingThenLoaded() async {
    let server = FakeSettingsServer()
    await server.hold()
    let source = FakeSettingsSource(connected: false)
    let model = SettingsGroupModel(server.group, source: source)
    #expect(model.phase == .notConnected)
    #expect(model.value == nil)

    source.connect()
    #expect(await eventually { model.phase == .loading })
    #expect(await eventually { await server.waiting == 1 })
    await server.release()
    #expect(await eventually { model.phase == .loaded })
    #expect(model.value == Queue(maxActiveDownloads: 3, maxActiveSeeds: 25))

    // Losing the connection: nothing to show, and nothing can be changed.
    source.settingsActions = nil
    #expect(await eventually { model.phase == .notConnected })
    #expect(model.value == nil)
    model.set(\.maxActiveSeeds, to: 1)
    #expect(await server.writes.isEmpty)
  }

  @Test func aNewConnectionReadsTheGroupAgain() async {
    let (model, source, server) = await loaded()
    await server.changeElsewhere(Queue(maxActiveDownloads: 9, maxActiveSeeds: 9))
    source.connect()
    #expect(await eventually { model.value?.maxActiveDownloads == 9 })
    #expect(await server.reads == 2)
  }

  @Test func aFailedLoadSaysWhyAndCanBeRetried() async {
    let server = FakeSettingsServer()
    await server.failNextRead(UmbraError(code: "x", message: "Umbra couldn't be reached."))
    let model = SettingsGroupModel(server.group, source: FakeSettingsSource())
    #expect(await eventually { model.phase == .loadFailed(message: "Umbra couldn't be reached.") })
    // It doesn't keep trying by itself.
    try? await Task.sleep(for: .milliseconds(20))
    #expect(await server.reads == 1)
    model.retry()
    #expect(await eventually { model.phase == .loaded })
  }

  // MARK: Switches and menus: sent at once

  @Test func setSendsTheWholeGroupAtOnce() async {
    let (model, _, server) = await loaded()
    model.set(\.maxActiveSeeds, to: 0)
    #expect(model.value?.maxActiveSeeds == 0)  // shown straight away
    #expect(await eventually { await server.writes.count == 1 })
    #expect(await server.writes == [Queue(maxActiveDownloads: 3, maxActiveSeeds: 0)])
    #expect(await eventually { !model.isSending })
  }

  @Test func aChangeThatChangesNothingIsNotSent() async {
    let (model, _, server) = await loaded()
    model.set(\.maxActiveSeeds, to: 25)
    model.set(\.maxActiveDownloads, to: 3)
    try? await Task.sleep(for: .milliseconds(20))
    #expect(await server.writes.isEmpty)
  }

  // MARK: Typed fields: sent when committed

  @Test func typingSendsNothingUntilCommitted() async {
    let (model, _, server) = await loaded()
    let format = SettingsFormat<Int>.wholeNumber()
    model.type("1", into: \.maxActiveDownloads)
    model.type("12", into: \.maxActiveDownloads)
    #expect(model.text(\.maxActiveDownloads, as: format) == "12")
    #expect(model.isTyping(in: \.maxActiveDownloads))
    try? await Task.sleep(for: .milliseconds(20))
    #expect(await server.writes.isEmpty)
    #expect(model.value?.maxActiveDownloads == 3)

    model.commit(\.maxActiveDownloads, as: format)
    #expect(!model.isTyping(in: \.maxActiveDownloads))
    #expect(await eventually { await server.writes.count == 1 })
    #expect(await server.writes.first?.maxActiveDownloads == 12)
  }

  @Test func textThatIsntANumberGoesBackWithoutSending() async {
    let (model, _, server) = await loaded()
    let format = SettingsFormat<Int>.wholeNumber()
    model.type("1.2.", into: \.maxActiveDownloads)
    model.commit(\.maxActiveDownloads, as: format)
    #expect(model.text(\.maxActiveDownloads, as: format) == "3")
    // Committing what's already there sends nothing either.
    model.type("3", into: \.maxActiveDownloads)
    model.commit(\.maxActiveDownloads, as: format)
    try? await Task.sleep(for: .milliseconds(20))
    #expect(await server.writes.isEmpty)
  }

  // MARK: Refusals

  @Test func aRefusalGoesBackAndSaysWhy() async {
    let (model, _, server) = await loaded()
    await server.refuseNext(refusedDownloads)
    model.set(\.maxActiveDownloads, to: 0)
    #expect(model.value?.maxActiveDownloads == 0)
    #expect(await eventually { model.refusal != nil })
    #expect(model.value?.maxActiveDownloads == 3)  // back to what Umbra has
    #expect(model.problem(for: "maxActiveDownloads") == "Enter a number from 1 to 50.")
    #expect(model.problem(for: "maxActiveSeeds") == nil)
    #expect(model.pageProblem == nil)  // the field's message says it all

    // The next change that's saved clears it.
    model.set(\.maxActiveSeeds, to: 5)
    #expect(await eventually { model.refusal == nil })
    #expect(model.value == Queue(maxActiveDownloads: 3, maxActiveSeeds: 5))
  }

  @Test func aRefusalNamingNoFieldIsForThePage() async {
    let (model, _, server) = await loaded()
    await server.refuseNext(UmbraError(code: "internal", message: "Something went wrong."))
    model.set(\.maxActiveSeeds, to: 1)
    #expect(await eventually { model.pageProblem == "Something went wrong." })
    #expect(model.value?.maxActiveSeeds == 25)
  }

  // MARK: One request at a time; the newest edit wins

  @Test func neverTwoRequestsAtOnceAndTheNewestEditWins() async {
    let (model, _, server) = await loaded()
    await server.hold()
    model.set(\.maxActiveDownloads, to: 4)
    #expect(await eventually { await server.waiting == 1 })
    // Three more while the first is on its way...
    model.set(\.maxActiveDownloads, to: 5)
    model.set(\.maxActiveSeeds, to: 9)
    model.set(\.maxActiveDownloads, to: 6)
    #expect(model.value == Queue(maxActiveDownloads: 6, maxActiveSeeds: 9))
    try? await Task.sleep(for: .milliseconds(20))
    #expect(await server.writes.count == 1)  // ...wait for it
    await server.release()
    #expect(await eventually { await server.writes.count == 2 && !model.isSending })
    // ...then go together, in one request, newest last.
    #expect(
      await server.writes == [
        Queue(maxActiveDownloads: 4, maxActiveSeeds: 25),
        Queue(maxActiveDownloads: 6, maxActiveSeeds: 9),
      ])
    #expect(await server.mostAtOnce == 1)
    #expect(model.value == Queue(maxActiveDownloads: 6, maxActiveSeeds: 9))
  }

  @Test func editsMadeAfterARefusedOneAreStillSent() async {
    let (model, _, server) = await loaded()
    await server.hold()
    await server.refuseNext(refusedDownloads)
    model.set(\.maxActiveDownloads, to: 0)
    #expect(await eventually { await server.waiting == 1 })
    model.set(\.maxActiveSeeds, to: 7)
    await server.release()
    #expect(await eventually { await server.writes.count == 2 && !model.isSending })
    // The second request didn't carry the refused value.
    #expect(await server.writes.last == Queue(maxActiveDownloads: 3, maxActiveSeeds: 7))
    #expect(model.value == Queue(maxActiveDownloads: 3, maxActiveSeeds: 7))
    #expect(model.refusal == nil)
  }

  // MARK: Changes made elsewhere

  @Test func aChangeNoticeReadsTheGroupAgain() async {
    let (model, source, server) = await loaded()
    await server.changeElsewhere(Queue(maxActiveDownloads: 8, maxActiveSeeds: 25))
    source.store.announceSettingsChanged("speed")  // another group: no read
    try? await Task.sleep(for: .milliseconds(20))
    #expect(await server.reads == 1)
    source.store.announceSettingsChanged("queue")
    #expect(await eventually { model.value?.maxActiveDownloads == 8 })
  }

  @Test func aChangeNoticeDoesNotClobberWhatIsBeingTyped() async {
    let (model, source, server) = await loaded()
    let format = SettingsFormat<Int>.wholeNumber(blank: 0)
    model.type("7", into: \.maxActiveDownloads)
    await server.changeElsewhere(Queue(maxActiveDownloads: 2, maxActiveSeeds: 40))
    source.store.announceSettingsChanged("queue")
    #expect(await eventually { model.value?.maxActiveSeeds == 40 })
    #expect(model.text(\.maxActiveDownloads, as: .wholeNumber()) == "7")
    #expect(model.text(\.maxActiveSeeds, as: format) == "40")
    // Committed, the typed value goes onto the latest group.
    model.commit(\.maxActiveDownloads, as: .wholeNumber())
    #expect(await eventually { await server.writes.count == 1 })
    #expect(await server.writes == [Queue(maxActiveDownloads: 7, maxActiveSeeds: 40)])
  }

  @Test func aChangeNoticeWhileSendingWaitsForTheAnswer() async {
    let (model, source, server) = await loaded()
    await server.hold()
    model.set(\.maxActiveSeeds, to: 1)
    #expect(await eventually { await server.waiting == 1 })
    source.store.announceSettingsChanged("queue")  // our own change, announced
    try? await Task.sleep(for: .milliseconds(20))
    #expect(await server.reads == 1)  // not read while the change is on its way
    await server.release()
    #expect(await eventually { await server.reads == 2 })
    #expect(await server.mostAtOnce == 1)
    #expect(model.value?.maxActiveSeeds == 1)
  }

  // MARK: Several listeners

  @Test func severalListenersAllHearAChange() async {
    let source = FakeSettingsSource()
    let queueServer = FakeSettingsServer()
    let otherServer = FakeSettingsServer()
    let window = MainWindowModel(store: source.store, defaults: throwawayDefaults())
    let queue = SettingsGroupModel(queueServer.group, source: source)
    let other = SettingsGroupModel(
      SettingsGroup<Queue>(
        name: "seeding",
        read: { _ async throws(UmbraError) in try await otherServer.read() },
        write: { value, _ async throws(UmbraError) in try await otherServer.write(value) }),
      source: source)
    #expect(await eventually { queue.phase == .loaded && other.phase == .loaded })

    source.store.announceSettingsChanged("queue")
    #expect(await eventually { await queueServer.reads == 2 })
    #expect(window.settingsChangeCount == 1)
    source.store.announceSettingsChanged("seeding")
    #expect(await eventually { await otherServer.reads == 2 })
    #expect(window.settingsChangeCount == 2)
    #expect(await queueServer.reads == 2)
  }

  @Test func aDroppedModelStopsListening() async {
    let source = FakeSettingsSource()
    var heard = 0
    var subscription: SettingsSubscription? = source.listenForSettingsChanges { _ in heard += 1 }
    source.store.announceSettingsChanged("queue")
    subscription = nil
    source.store.announceSettingsChanged("queue")
    #expect(heard == 1)
    #expect(subscription == nil)
  }

  @Test func theAppKeepsOneModelPerGroup() {
    let models = SettingsModels(source: FakeSettingsSource(connected: false))
    #expect(models.model(for: .queue) === models.model(for: .queue))
    #expect(models.model(for: .queue).group.name == "queue")
    #expect(models.model(for: .seeding).phase == .notConnected)
  }

  @Test func aPageWithSeveralGroupsShowsTheWorstState() {
    #expect(SettingsPhase.combined([.loaded, .loaded]) == .loaded)
    #expect(SettingsPhase.combined([.loaded, .loading]) == .loading)
    #expect(
      SettingsPhase.combined([.loading, .loadFailed(message: "x")]) == .loadFailed(message: "x"))
    #expect(SettingsPhase.combined([.loadFailed(message: "x"), .notConnected]) == .notConnected)
  }

  @Test func aFixtureShowsItsValueAndSendsNothing() {
    let model = SettingsGroupModel(
      .queue, fixture: Queue(maxActiveDownloads: 3, maxActiveSeeds: 0), refusal: refusedDownloads)
    #expect(model.phase == .loaded)
    #expect(model.problem(for: "maxActiveDownloads") != nil)
    model.set(\.maxActiveDownloads, to: 4)
    #expect(model.value?.maxActiveDownloads == 3)
  }
}

/// Showing settings as text and reading typed text back.
@Suite struct SettingsFormatTests {
  let posix = Locale(identifier: "en_US_POSIX")

  func read<T>(_ format: SettingsFormat<T>, _ text: String) -> T? {
    if case .value(let value) = format.read(text) { return value }
    return nil
  }

  @Test func wholeNumbers() {
    let plain = SettingsFormat<Int>.wholeNumber()
    #expect(plain.text(3) == "3")
    #expect(read(plain, " 12 ") == 12)
    #expect(read(plain, "2.6") == 3)  // rounded, as the web page does
    #expect(read(plain, "-1") == -1)  // Umbra decides whether it's allowed
    #expect(read(plain, "") == nil)
    #expect(read(plain, "abc") == nil)
    #expect(read(plain, "1e400") == nil)

    let noLimit = SettingsFormat<Int>.wholeNumber(blank: 0)
    #expect(noLimit.text(0) == "")
    #expect(noLimit.text(25) == "25")
    #expect(read(noLimit, "") == 0)
  }

  @Test func optionalNumbers() {
    let minutes = SettingsFormat<Int?>.optionalWholeNumber
    #expect(minutes.text(nil) == "")
    #expect(minutes.text(30) == "30")
    #expect(read(minutes, "") == .some(nil))
    #expect(read(minutes, "45") == 45)
    #expect(read(minutes, "x") == nil)

    let ratio = SettingsFormat<Double?>.optionalDecimal(locale: posix)
    #expect(ratio.text(1.5) == "1.5")
    #expect(ratio.text(2) == "2")
    #expect(ratio.text(nil) == "")
    #expect(read(ratio, "1,5") == 1.5)
    #expect(read(ratio, "0.25") == 0.25)
    #expect(read(ratio, "") == .some(nil))
  }

  @Test func hoursAreKeptAsMinutes() {
    let hours = SettingsFormat<Int?>.optionalHoursAsMinutes(locale: posix)
    #expect(hours.text(90) == "1.5")
    #expect(hours.text(10080) == "168")
    #expect(hours.text(100) == "1.67")
    #expect(read(hours, "1.5") == 90)
    #expect(read(hours, "168") == 10080)
    #expect(read(hours, "") == .some(nil))
  }

  @Test func textAndSecrets() {
    #expect(read(SettingsFormat<String>.text, " /a b ") == " /a b ")
    let secret = SettingsFormat<SecretChange>.newSecret
    #expect(secret.text(.replaced("hunter2")) == "")
    #expect(read(secret, "") == .unchanged)
    #expect(read(secret, "pw") == .replaced("pw"))
  }
}
