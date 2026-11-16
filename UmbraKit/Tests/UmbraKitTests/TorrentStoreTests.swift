import Foundation
import Observation
import Synchronization
import Testing
import UmbraAPI

@testable import UmbraKit

@MainActor @Suite struct TorrentStoreTests {
  let connection = Connection(
    baseURL: URL(string: "http://127.0.0.1:7979")!, credential: .launchToken("t"))
  let dropTime = Date(timeIntervalSince1970: 1000)

  /// A store whose batching wait returns at once (no real waiting).
  func makeStore() -> TorrentStore {
    TorrentStore(sleep: { _ in await Task.yield() }, now: { [dropTime] in dropTime })
  }

  @Test func aBurstOfUpdatesIsOneChange() async throws {
    let store = makeStore()
    // Views watching the list are told it changed (Observation tells them
    // once per change they're watching; `batchCount` counts the changes).
    let told = Mutex(0)
    withObservationTracking {
      _ = store.torrents
    } onChange: {
      told.withLock { $0 += 1 }
    }

    store.receive(.opened)
    store.receive(.event(snapshot(rev: 1, [row("a", "a")])))
    for rev in 2...200 {
      store.receive(
        .event(delta(from: Int64(rev - 1), rev: Int64(rev), changed: [row("h\(rev)", "\(rev)")])))
    }
    store.receive(.event(.transfer(transfer())))
    #expect(store.torrents.isEmpty)  // nothing put in until the batch wait ends

    try await #require(store.flushTask).value
    #expect(store.batchCount == 1)
    #expect(told.withLock { $0 } == 1)
    #expect(store.torrents.count == 200)
    #expect(store.feed.rev == 200)
    #expect(store.state == .live)
    #expect(store.vpn == .connected)
  }

  @Test func aRefusalIsShownAsRefused() async throws {
    let store = makeStore()
    store.receive(.opened)
    store.receive(.refused(status: 401))
    try await #require(store.flushTask).value
    #expect(store.state == .refused)
  }

  @Test func updatesAfterABatchStartTheNextBatch() async throws {
    let store = makeStore()
    store.receive(.event(snapshot(rev: 1, [])))
    try await #require(store.flushTask).value
    store.receive(.event(delta(from: 1, rev: 2, changed: [row("a", "a")])))
    try await #require(store.flushTask).value
    #expect(store.batchCount == 2)
    #expect(store.torrent(hash: "a")?.name == "a")
  }

  @Test func stateGoesConnectingLiveReconnectingLive() async throws {
    let source = FakeByteSource([
      .send([wire(snapshot(rev: 1, [row("a", "a")]))]),
      .sendAndHold([wire(snapshot(rev: 5, [row("b", "b")]))]),
    ])
    // The feed's own retry wait is held until the test has seen "reconnecting".
    let gate = Gate()
    let client = FeedClient(connection: connection, source: source) { _ in await gate.wait() }
    let store = makeStore()
    store.start(client: client)
    #expect(store.state == .connecting)

    #expect(await eventually { store.state == .reconnecting(since: dropTime) })
    // The list received before the drop stays while reconnecting.
    #expect(store.torrents.map(\.hash) == ["a"])

    await gate.open()
    #expect(await eventually { store.state == .live && store.feed.rev == 5 })
    // The fresh snapshot replaced the old list.
    #expect(store.torrents.map(\.hash) == ["b"])

    store.stop()
    #expect(store.state == .connecting)
    #expect(await eventually { source.stopped == 1 })
  }

  @Test func missedDeltaFetchesTheListAgain() async throws {
    let source = FakeByteSource(
      [
        .sendAndHold([
          wire(snapshot(rev: 1, [row("a", "a")])),
          wire(delta(from: 3, rev: 4, changed: [row("x", "x")])),  // 2 and 3 were missed
        ])
      ],
      snapshotBody: #"{"rev":4,"torrents":[]}"#)
    let store = makeStore()
    store.start(client: FeedClient(connection: connection, source: source))
    #expect(await eventually { store.feed.rev == 4 })
    #expect(store.torrents.isEmpty)
    store.stop()
  }

  @Test func finishedAndSettingsChangedReachTheirListeners() async throws {
    let store = makeStore()
    var finished: [String] = []
    var groups: [String] = []
    store.onTorrentFinished = { finished.append($0.hash) }
    let listening = store.listenForSettingsChanges { groups.append($0) }
    store.receive(.event(.finished(.init(hash: "a", name: "A", size: 1))))
    store.receive(.event(.settingsChanged(group: "security")))
    try await #require(store.flushTask).value
    #expect(finished == ["a"])
    #expect(groups == ["security"])
    listening.cancel()
  }

  @Test func stopDropsWhatWasWaitingAndKeepsTheList() async throws {
    let store = makeStore()
    store.receive(.event(snapshot(rev: 1, [row("a", "a")])))
    try await #require(store.flushTask).value
    store.receive(.event(snapshot(rev: 2, [])))
    store.stop()
    #expect(store.flushTask == nil)
    #expect(store.torrents.map(\.hash) == ["a"])
    #expect(store.state == .connecting)
  }

  @Test func patchAndSetCreationsApplyAtOnce() {
    let store = makeStore()
    store.patch([row("a", "a")])
    store.setCreations([])
    #expect(store.torrent(hash: "a") != nil)
    #expect(store.creations == [])
  }
}

/// Holds whoever waits on it until the test opens it.
actor Gate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    if isOpen { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func open() {
    isOpen = true
    for waiter in waiters { waiter.resume() }
    waiters = []
  }
}
