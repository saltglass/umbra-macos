import Foundation

/// Somewhere the feed's bytes come from.
///
/// The real one is `URLSessionByteSource`. Tests use a stand-in that plays back
/// prepared bytes, so they need no network and no running Umbra.
public protocol FeedByteSource: Sendable {
  /// Sends `request`. Once the server has answered "200 OK", calls `opened`,
  /// then `received` with each piece of the body as it arrives (pieces may be
  /// cut anywhere). Returns when the body ends; throws if the request fails,
  /// the server answers anything other than 200, or the connection breaks.
  /// Stops promptly when the calling task is cancelled.
  func read(
    _ request: URLRequest,
    opened: () async -> Void,
    received: ([UInt8]) async throws -> Void
  ) async throws
}

/// The server answered with something other than "200 OK".
public struct FeedHTTPError: Error, Sendable, Equatable {
  public let status: Int
}

/// Reads with Apple's URLSession.
public struct URLSessionByteSource: FeedByteSource {
  let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func read(
    _ request: URLRequest,
    opened: () async -> Void,
    received: ([UInt8]) async throws -> Void
  ) async throws {
    let (bytes, response) = try await session.bytes(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else {
      bytes.task.cancel()
      throw FeedHTTPError(status: status)
    }
    await opened()

    // URLSession hands over one byte at a time. Pass them on a line at a
    // time: every feed message ends with a line break, so nothing is held
    // back waiting, and the parser isn't called once per byte. A very long
    // line (the snapshot of thousands of torrents is one line) goes in
    // large pieces.
    var piece: [UInt8] = []
    piece.reserveCapacity(4096)
    for try await byte in bytes {
      piece.append(byte)
      if byte == 0x0A || byte == 0x0D || piece.count >= 65_536 {
        try await received(piece)
        piece.removeAll(keepingCapacity: true)
      }
    }
    if !piece.isEmpty { try await received(piece) }
  }
}
