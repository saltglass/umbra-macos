import Foundation
import HTTPTypes
import Testing
import UmbraAPI

@testable import UmbraKit

@Suite struct FeedClientTests {
  let connection = Connection(
    baseURL: URL(string: "http://127.0.0.1:7979")!, credential: .launchToken("tok-123"))

  /// Reads updates until `count` have arrived, then stops reading.
  func collect(_ client: FeedClient, count: Int) async throws -> [FeedClient.Update] {
    var updates: [FeedClient.Update] = []
    for try await update in client.updates() {
      updates.append(update)
      if updates.count == count { break }
    }
    return updates
  }

  @Test func opensTheEventsAddressWithTheCredential() async throws {
    let source = FakeByteSource([.sendAndHold([])])
    let client = FeedClient(connection: connection, source: source)
    _ = try await collect(client, count: 1)
    let request = try #require(source.requests.first)
    #expect(request.url?.absoluteString == "http://127.0.0.1:7979/api/v1/events")
    #expect(request.value(forHTTPHeaderField: "X-Umbra-Launch-Token") == "tok-123")
    #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
  }

  @Test func snapshotThenDeltas() async throws {
    let text =
      "retry: 5000\n\n" + wire(snapshot(rev: 1, [row("a", "a")]))
      + ": keep-alive\n\n" + wire(delta(from: 1, rev: 2, changed: [row("b", "b")]))
      + wire(.transfer(transfer()))
    // Cut into small pieces, as the network might.
    let bytes = Array(text.utf8)
    let pieces = stride(from: 0, to: bytes.count, by: 7).map {
      String(decoding: bytes[$0..<min($0 + 7, bytes.count)], as: UTF8.self)
    }
    // Cutting bytes and turning them back into text is only safe for plain ASCII.
    #expect(pieces.joined() == text)
    let source = FakeByteSource([.sendAndHold(pieces)])
    let updates = try await collect(FeedClient(connection: connection, source: source), count: 4)
    #expect(
      updates == [
        .opened,
        .event(snapshot(rev: 1, [row("a", "a")])),
        .event(delta(from: 1, rev: 2, changed: [row("b", "b")])),
        .event(.transfer(transfer())),
      ])
  }

  @Test func unreadableMessageIsSkipped() async throws {
    let source = FakeByteSource([
      .sendAndHold([
        "event: torrents.delta\ndata: {oops\n\n", "event: new.kind\ndata: 1\n\n",
        wire(.settingsChanged(group: "g")),
      ])
    ])
    let updates = try await collect(FeedClient(connection: connection, source: source), count: 2)
    #expect(updates == [.opened, .event(.settingsChanged(group: "g"))])
  }

  @Test func dropThenReconnectStartsFromAFreshSnapshot() async throws {
    let sleeper = RecordingSleeper()
    let source = FakeByteSource([
      // Half a message, then the connection ends: the half must not leak into the next one.
      .send([wire(snapshot(rev: 1, [row("a", "a")])), "event: torrents.delta\ndata: {\"fr"]),
      .sendAndHold([wire(snapshot(rev: 7, [row("b", "b")]))]),
    ])
    let client = FeedClient(connection: connection, source: source, sleep: sleeper.sleep)
    let updates = try await collect(client, count: 5)
    #expect(
      updates == [
        .opened,
        .event(snapshot(rev: 1, [row("a", "a")])),
        .dropped(retryIn: .seconds(1)),
        .opened,
        .event(snapshot(rev: 7, [row("b", "b")])),
      ])
    #expect(source.requests.count == 2)
  }

  @Test func backoffDoublesFromOneSecondToThirty() async throws {
    let sleeper = RecordingSleeper()
    let source = FakeByteSource(Array(repeating: .fail, count: 8))
    let client = FeedClient(connection: connection, source: source, sleep: sleeper.sleep)
    let updates = try await collect(client, count: 8)
    let waits: [Duration] = [1, 2, 4, 8, 16, 30, 30, 30].map { .seconds($0) }
    #expect(updates == waits.map { .dropped(retryIn: $0) })
    #expect(Array(sleeper.recorded.prefix(7)) == Array(waits.prefix(7)))
  }

  @Test func backoffStartsAgainAfterASnapshot() async throws {
    let sleeper = RecordingSleeper()
    let source = FakeByteSource([
      .fail, .fail,
      .send([wire(snapshot(rev: 1, []))]),  // worked, then dropped
      .fail,
      // Opened, but no snapshot before it dropped: doesn't count as working.
      .send([]),
      .fail,
    ])
    let client = FeedClient(connection: connection, source: source, sleep: sleeper.sleep)
    var waits: [Duration] = []
    for try await update in client.updates() {
      if case .dropped(let wait) = update { waits.append(wait) }
      if waits.count == 6 { break }
    }
    #expect(waits == [1, 2, 1, 2, 4, 8].map { .seconds($0) })
  }

  @Test func stoppingReadingClosesTheConnection() async throws {
    let source = FakeByteSource([.sendAndHold([wire(snapshot(rev: 1, []))])])
    let updates = try await collect(FeedClient(connection: connection, source: source), count: 2)
    #expect(updates.count == 2)
    #expect(await eventually { source.stopped == 1 })
    #expect(source.requests.count == 1)  // and it did not reconnect
  }

  @Test func cancellingTheReadingTaskEndsTheStreamCleanly() async throws {
    let source = FakeByteSource([.sendAndHold([])])
    let client = FeedClient(connection: connection, source: source)
    let task = Task {
      var count = 0
      for try await _ in client.updates() { count += 1 }
      return count  // reached only if the stream finished rather than threw
    }
    #expect(await eventually { source.requests.count == 1 })
    task.cancel()
    let count = try await task.value
    #expect(count <= 1)
    #expect(await eventually { source.stopped == 1 })
  }

  @Test func cancellingDuringTheWaitStops() async throws {
    let source = FakeByteSource(Array(repeating: .fail, count: 100))
    // A wait that only ends when cancelled.
    let client = FeedClient(connection: connection, source: source) { _ in
      let (never, continuation) = AsyncStream<Never>.makeStream()
      for await _ in never {}
      continuation.finish()
      try Task.checkCancellation()
    }
    let task = Task { for try await _ in client.updates() {} }
    #expect(await eventually { source.requests.count == 1 })
    task.cancel()
    try await task.value
    #expect(source.requests.count == 1)
  }

  @Test(arguments: [401, 403])
  func aRefusedCredentialStopsRetrying(status: Int) async throws {
    let sleeper = RecordingSleeper()
    // One ordinary failure (retried), then the refusal, then a stream that
    // would work: it must never be opened.
    let source = FakeByteSource([.fail, .status(status), .sendAndHold([])])
    let client = FeedClient(connection: connection, source: source, sleep: sleeper.sleep)
    var updates: [FeedClient.Update] = []
    for try await update in client.updates() { updates.append(update) }  // ends by itself
    #expect(updates == [.dropped(retryIn: .seconds(1)), .refused(status: status)])
    #expect(source.requests.count == 2)
    #expect(sleeper.recorded == [.seconds(1)])
  }

  @Test(arguments: [404, 500, 503])
  func otherStatusesKeepTheBackoff(status: Int) async throws {
    let sleeper = RecordingSleeper()
    let source = FakeByteSource([.status(status), .status(status), .sendAndHold([])])
    let client = FeedClient(connection: connection, source: source, sleep: sleeper.sleep)
    let updates = try await collect(client, count: 3)
    #expect(updates == [.dropped(retryIn: .seconds(1)), .dropped(retryIn: .seconds(2)), .opened])
  }

  @Test func fetchSnapshotReadsTorrentsWithTheCredential() async throws {
    let body = #"{"rev":4,"torrents":[]}"#
    let source = FakeByteSource([], snapshotBody: body)
    let snap = try await FeedClient(connection: connection, source: source).fetchSnapshot()
    #expect(snap == .init(rev: 4, torrents: []))
  }

  @Test func requestHelperUsesTheSameHeaderAsTheGeneratedClient() {
    let request = Connection(baseURL: URL(string: "http://h/")!, credential: .apiKey("k"))
      .request(path: "torrents")
    #expect(request.url?.absoluteString == "http://h/api/v1/torrents")
    #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "k")
  }
}
