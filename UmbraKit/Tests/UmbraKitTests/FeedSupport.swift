import Foundation
import Synchronization
import UmbraAPI

@testable import UmbraKit

/// A torrent row with only the parts a test cares about.
func row(_ hash: String, _ name: String = "") -> Components.Schemas.Torrent {
  .init(
    hash: hash, name: name, size: 0, progress: 0, state: .downloading, downSpeed: 0, upSpeed: 0,
    ratio: 0, category: "", tags: [], addedAt: Date(timeIntervalSince1970: 0), savePath: "",
    seeds: 0, seedsTotal: 0, peers: 0, peersTotal: 0, downloaded: 0, uploaded: 0,
    seedTimeSeconds: 0, queuePosition: 0)
}

func snapshot(rev: Int64, _ rows: [Components.Schemas.Torrent]) -> FeedEvent {
  .snapshot(.init(rev: rev, torrents: rows))
}

func delta(
  from: Int64, rev: Int64, changed: [Components.Schemas.Torrent] = [], removed: [String] = []
) -> FeedEvent {
  .delta(.init(from: from, rev: rev, changed: changed, removed: removed))
}

func transfer(vpn: Components.Schemas.VpnState = .connected) -> Components.Schemas.Transfer {
  .init(
    downSpeed: 1, upSpeed: 2, downLimit: 0, upLimit: 0, slowMode: false, sessionDownloaded: 0,
    sessionUploaded: 0, freeSpace: 0, lowSpace: 0, incoming: true, dhtNodes: 0, vpn: vpn)
}

/// A message as Umbra writes it on the wire (see `write` in Umbra's events.go).
func wire(_ event: FeedEvent) -> String {
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  func json(_ value: some Encodable) -> String {
    String(decoding: try! encoder.encode(value), as: UTF8.self)
  }
  let (name, data): (String, String) =
    switch event {
    case .snapshot(let s): (FeedEvent.Name.snapshot, json(s))
    case .delta(let d): (FeedEvent.Name.delta, json(d))
    case .transfer(let t): (FeedEvent.Name.transfer, json(t))
    case .creations(let c): (FeedEvent.Name.creations, json(c))
    case .finished(let f): (FeedEvent.Name.finished, json(f))
    case .settingsChanged(let g): (FeedEvent.Name.settingsChanged, #"{"group":"\#(g)"}"#)
    }
  return "event: \(name)\ndata: \(data)\n\n"
}

/// A stand-in for the network. Each time the feed is opened it plays the
/// next prepared connection; once they run out, it holds the connection open
/// and silent until the reader stops.
final class FakeByteSource: FeedByteSource {
  enum Script: Sendable {
    /// The request fails before the server answers.
    case fail
    /// The server answers with this HTTP status instead of 200.
    case status(Int)
    /// The server answers, sends these pieces, then the connection ends.
    case send([String])
    /// The server answers, sends these pieces, then stays open and silent.
    case sendAndHold([String])
  }

  private struct State {
    var scripts: [Script]
    var requests: [URLRequest] = []
    var stopped = 0
  }
  // A Mutex makes the shared state safe to touch from any task.
  private let state: Mutex<State>
  private let snapshotBody: String

  init(_ scripts: [Script], snapshotBody: String = "") {
    state = Mutex(State(scripts: scripts))
    self.snapshotBody = snapshotBody
  }

  var requests: [URLRequest] { state.withLock { $0.requests } }
  /// How many held connections ended because the reader stopped.
  var stopped: Int { state.withLock { $0.stopped } }

  struct Failed: Error {}

  func read(
    _ request: URLRequest, opened: () async -> Void, received: ([UInt8]) async throws -> Void
  ) async throws {
    if request.url?.lastPathComponent == "torrents" {
      await opened()
      try await received(Array(snapshotBody.utf8))
      return
    }
    let script = state.withLock { state -> Script in
      state.requests.append(request)
      return state.scripts.isEmpty ? .sendAndHold([]) : state.scripts.removeFirst()
    }
    switch script {
    case .fail:
      throw Failed()
    case .status(let code):
      throw FeedHTTPError(status: code)
    case .send(let pieces):
      await opened()
      for piece in pieces { try await received(Array(piece.utf8)) }
    case .sendAndHold(let pieces):
      await opened()
      for piece in pieces { try await received(Array(piece.utf8)) }
      // Wait until cancelled: reading a stream that never yields ends when
      // the reading task is cancelled.
      let (never, continuation) = AsyncStream<Never>.makeStream()
      for await _ in never {}
      continuation.finish()
      state.withLock { $0.stopped += 1 }
    }
  }
}

/// Notes every wait asked for, and returns at once (no real waiting).
final class RecordingSleeper: Sendable {
  private let waits = Mutex<[Duration]>([])
  var recorded: [Duration] { waits.withLock { $0 } }

  var sleep: FeedClient.Sleep {
    { [self] duration in
      waits.withLock { $0.append(duration) }
      try Task.checkCancellation()
      await Task.yield()
    }
  }
}

/// Waits until `condition` holds, checking every millisecond, for up to a second.
@MainActor
func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
  for _ in 0..<1000 {
    if condition() { return true }
    try? await Task.sleep(for: .milliseconds(1))
  }
  return condition()
}
