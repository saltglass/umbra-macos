import Foundation
import UmbraAPI
import os

/// Keeps Umbra's live feed (`GET /api/v1/events`) open and hands on what it says.
///
/// If the stream drops, it waits (1 s, 2 s, 4 s ... up to 30 s) and opens it
/// again; the server starts every new stream with a fresh snapshot of every
/// torrent, so nothing missed while it was down stays missing.
///
/// The one exception: if the server says our credential is wrong (401 or
/// 403), retrying can never help, so it says `.refused` and stops.
public struct FeedClient: Sendable {
  /// What the feed tells its reader.
  public enum Update: Sendable, Equatable {
    /// The server answered: the stream is open.
    case opened
    /// A message arrived.
    case event(FeedEvent)
    /// The stream broke or ended; it will be opened again after `retryIn`.
    case dropped(retryIn: Duration)
    /// The server turned the credential away (HTTP `status`, 401 or 403).
    /// The feed stops: asking again with the same credential can't work.
    /// This is always the last update.
    case refused(status: Int)
  }

  /// Waits for a length of time. Real use waits on the clock; tests pass one
  /// that returns at once and notes the waits asked for.
  public typealias Sleep = @Sendable (Duration) async throws -> Void

  private let streamRequest: URLRequest
  private let snapshotRequest: URLRequest
  private let source: any FeedByteSource
  private let sleep: Sleep

  private static let log = Logger(subsystem: "UmbraKit", category: "feed")

  public init(
    connection: Connection,
    source: any FeedByteSource = URLSessionByteSource(),
    sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
  ) {
    var stream = connection.request(path: "events")
    stream.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    stream.cachePolicy = .reloadIgnoringLocalCacheData
    // URLSession gives up on a request that receives nothing for this long.
    // Umbra sends a keep-alive line every 25 s, so a minute of silence
    // means the connection is dead, and dropping it starts a reconnect.
    stream.timeoutInterval = 60
    var snapshot = connection.request(path: "torrents")
    snapshot.setValue("application/json", forHTTPHeaderField: "Accept")
    self.streamRequest = stream
    self.snapshotRequest = snapshot
    self.source = source
    self.sleep = sleep
  }

  /// The feed's updates, for as long as they are read. It retries until the
  /// credential is refused; stopping reading it (or cancelling the task
  /// reading it) closes the connection. It never ends with an error.
  public func updates() -> AsyncThrowingStream<Update, any Error> {
    let (stream, continuation) = AsyncThrowingStream.makeStream(of: Update.self)
    let task = Task { [self] in
      await run(continuation)
      continuation.finish()
    }
    continuation.onTermination = { _ in task.cancel() }
    return stream
  }

  private func run(_ continuation: AsyncThrowingStream<Update, any Error>.Continuation) async {
    var backoff = FeedBackoff()
    while !Task.isCancelled {
      // A fresh reader for every connection: a half-read message from a
      // broken one must not be glued onto the next.
      var parser = SSEParser()
      do {
        try await source.read(
          streamRequest,
          opened: { continuation.yield(.opened) },
          received: { bytes in
            for message in parser.push(bytes) {
              guard let event = Self.decode(message) else { continue }
              // Only a snapshot proves the reconnection really worked.
              if case .snapshot = event { backoff.reset() }
              continuation.yield(.event(event))
            }
          }
        )
      } catch let error as FeedHTTPError where Self.isRefusal(error.status) {
        Self.log.error("Live feed refused: HTTP \(error.status, privacy: .public)")
        continuation.yield(.refused(status: error.status))
        return
      } catch {
        if !Task.isCancelled {
          Self.log.info("Live feed dropped: \(String(describing: error), privacy: .public)")
        }
      }
      if Task.isCancelled { return }

      let wait = backoff.next()
      continuation.yield(.dropped(retryIn: wait))
      do {
        try await sleep(wait)
      } catch {
        return  // cancelled while waiting
      }
    }
  }

  /// 401 (who are you?) and 403 (not allowed): the credential is the problem.
  static func isRefusal(_ status: Int) -> Bool { status == 401 || status == 403 }

  private static func decode(_ message: ServerSentEvent) -> FeedEvent? {
    do {
      return try FeedEvent(message)
    } catch {
      // The web app loses a message it can't read too. A lost delta is
      // noticed at the next one, which then doesn't follow on, and the
      // list is fetched again.
      log.error(
        "Couldn't read a \(message.type, privacy: .public) message: \(String(describing: error), privacy: .public)"
      )
      return nil
    }
  }

  /// Fetches the whole list (GET /torrents): what the web app does when a
  /// delta shows something was missed.
  ///
  /// This goes through the same byte source and JSON reader as the stream,
  /// so the feed needs only one way of reaching the server (and tests need
  /// only one stand-in for it).
  public func fetchSnapshot() async throws -> Components.Schemas.TorrentsSnapshot {
    var body: [UInt8] = []
    try await source.read(snapshotRequest, opened: {}, received: { body.append(contentsOf: $0) })
    return try FeedJSON.decoder.decode(Components.Schemas.TorrentsSnapshot.self, from: Data(body))
  }
}
