import Foundation
import Synchronization
import UmbraAPI

/// Plays a `StressFeed` as if it were Umbra's live feed: the same bytes
/// Umbra would send (a snapshot, then a delta and the totals every second),
/// so the app reads it through exactly the same code as the real thing.
/// Development only; see `DevStress`.
public final class StressByteSource: FeedByteSource {
  /// The list, shared between the stream and a refetch of the whole list.
  /// A Mutex makes it safe to touch from any task.
  private let feed: Mutex<StressFeed>
  private let interval: Duration
  private let sleep: FeedClient.Sleep

  /// - Parameters:
  ///   - feed: the made-up list to play.
  ///   - interval: the time between changes (a second, as Umbra's feed).
  ///   - sleep: how to wait; tests pass one that doesn't really wait.
  public init(
    feed: StressFeed,
    interval: Duration = .seconds(1),
    sleep: @escaping FeedClient.Sleep = { try await Task.sleep(for: $0) }
  ) {
    self.feed = Mutex(feed)
    self.interval = interval
    self.sleep = sleep
  }

  public func read(
    _ request: URLRequest,
    opened: () async -> Void,
    received: ([UInt8]) async throws -> Void
  ) async throws {
    // "GET /torrents": the whole list, after a missed update.
    if request.url?.lastPathComponent == "torrents" {
      await opened()
      try await received(Array(Self.json(feed.withLock { $0.snapshot }).utf8))
      return
    }
    await opened()
    let (snapshot, transfer) = feed.withLock { ($0.snapshot, $0.transfer) }
    try await received(Self.message("torrents.snapshot", snapshot))
    try await received(Self.message("transfer", transfer))
    while true {
      try await sleep(interval)
      try Task.checkCancellation()
      let (delta, transfer) = feed.withLock { feed in (feed.step(), feed.transfer) }
      try await received(Self.message("torrents.delta", delta))
      try await received(Self.message("transfer", transfer))
    }
  }

  /// One message as Umbra writes it on the wire.
  static func message(_ event: String, _ value: some Encodable) -> [UInt8] {
    Array("event: \(event)\ndata: \(json(value))\n\n".utf8)
  }

  static func json(_ value: some Encodable) -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    // Encoding the generated types can't fail; an empty object would just be skipped.
    return (try? String(decoding: encoder.encode(value), as: UTF8.self)) ?? "{}"
  }
}

/// Running a development build on the stress feed instead of a helper.
public enum DevStress {
  /// The stress feed, if `UMBRA_DEV_STRESS=1` is set. `UMBRA_DEV_STRESS_SEED`
  /// picks another list (any whole number).
  public static func source(from environment: [String: String], now: Date = Date())
    -> StressByteSource?
  {
    guard environment["UMBRA_DEV_STRESS"] == "1" else { return nil }
    let seed = environment["UMBRA_DEV_STRESS_SEED"].flatMap(UInt64.init) ?? 1
    return StressByteSource(feed: StressFeed(seed: seed, start: now))
  }

  /// A connection that goes nowhere: the stress feed answers instead.
  public static let connection = Connection(
    baseURL: URL(string: "http://127.0.0.1:9")!, credential: .apiKey("stress"))
}
