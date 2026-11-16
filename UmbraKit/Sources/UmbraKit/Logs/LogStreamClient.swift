import Foundation
import UmbraAPI
import os

/// Keeps Umbra's live log (`GET /api/v1/logs/stream`) open and hands on
/// each new line.
///
/// It reads the stream the same way the torrent feed does (`SSEParser`,
/// `FeedByteSource`, `FeedBackoff`). If the stream drops it waits (1 s,
/// 2 s, 4 s ... up to 30 s) and opens it again, asking for the lines after
/// the newest one the reader has, so nothing is missed in between.
///
/// A 401 or 403 means the credential is wrong: it stops and says so.
struct LogStreamClient: Sendable {
  enum Update: Sendable, Equatable {
    case opened
    case line(Components.Schemas.LogEntry)
    case dropped(retryIn: Duration)
    case refused(status: Int)
  }

  /// The name of a log line's message on the stream.
  static let eventName = "log"
  /// A connection that stayed open this long counts as working, so the
  /// next wait starts from one second again.
  static let healthyAfter: Duration = .seconds(5)

  private let connection: Connection
  private let source: any FeedByteSource
  private let sleep: FeedClient.Sleep

  private static let log = Logger(subsystem: "UmbraKit", category: "logs")

  init(connection: Connection, source: any FeedByteSource, sleep: @escaping FeedClient.Sleep) {
    self.connection = connection
    self.source = source
    self.sleep = sleep
  }

  /// The updates, until the reader stops reading (which closes the
  /// connection). `after` is asked before every connection for the newest
  /// line number the reader has.
  func updates(after: @escaping @Sendable () async -> Int64?) -> AsyncStream<Update> {
    let (stream, continuation) = AsyncStream.makeStream(of: Update.self)
    let task = Task { [self] in
      await run(after: after, continuation)
      continuation.finish()
    }
    continuation.onTermination = { _ in task.cancel() }
    return stream
  }

  private func request(after: Int64?) -> URLRequest {
    var request = connection.request(path: "logs/stream")
    if let after, let url = request.url,
      var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
    {
      parts.queryItems = [URLQueryItem(name: "after", value: String(after))]
      request.url = parts.url
    }
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    request.cachePolicy = .reloadIgnoringLocalCacheData
    // Umbra sends a keep-alive every 25 s; a minute of silence means dead.
    request.timeoutInterval = 60
    return request
  }

  private func run(
    after: @Sendable () async -> Int64?, _ continuation: AsyncStream<Update>.Continuation
  ) async {
    var backoff = FeedBackoff()
    let clock = ContinuousClock()
    while !Task.isCancelled {
      var parser = SSEParser()
      var openedAt: ContinuousClock.Instant?
      let request = request(after: await after())
      do {
        try await source.read(
          request,
          opened: {
            openedAt = clock.now
            continuation.yield(.opened)
          },
          received: { bytes in
            for message in parser.push(bytes) where message.type == Self.eventName {
              do {
                let entry = try FeedJSON.decoder.decode(
                  Components.Schemas.LogEntry.self, from: Data(message.data.utf8))
                continuation.yield(.line(entry))
              } catch {
                Self.log.error(
                  "Couldn't read a log line: \(String(describing: error), privacy: .public)")
              }
            }
          })
      } catch let error as FeedHTTPError where FeedClient.isRefusal(error.status) {
        continuation.yield(.refused(status: error.status))
        return
      } catch {
        if !Task.isCancelled {
          Self.log.info("Log stream dropped: \(String(describing: error), privacy: .public)")
        }
      }
      if Task.isCancelled { return }
      if let openedAt, clock.now - openedAt >= Self.healthyAfter { backoff.reset() }

      let wait = backoff.next()
      continuation.yield(.dropped(retryIn: wait))
      do { try await sleep(wait) } catch { return }
    }
  }
}
