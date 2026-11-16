import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import UmbraAPI

/// The calls the Create Torrent sheet makes to Umbra. Each is one request.
///
/// The Mac app never reads the files or builds a .torrent itself: Umbra
/// does all of it. The sheet only gives Umbra a path on this Mac (the
/// helper runs here and reads it directly). It never uses Umbra's upload
/// calls or its folder browser.
///
/// Each call either works or throws an `UmbraError` whose `message` (and
/// `fields`) are Umbra's own words.
public struct CreateTorrentActions: Sendable {
  public typealias Preview = Components.Schemas.CreationPreview
  public typealias Creation = Components.Schemas.Creation

  private let client: Client

  public init(connection: Connection) {
    self.init(connection: connection, transport: URLSessionTransport())
  }

  /// Same, over a transport of the caller's choosing (tests use a fake one).
  public init(connection: Connection, transport: any ClientTransport) {
    client = connection.makeClient(
      transport: transport, extraMiddlewares: [ServerErrorMiddleware()])
  }

  /// What a torrent of this file or folder would hold. Nothing is read.
  /// `pieceLength` is in bytes; nil or 0 is Automatic.
  public func preview(path: String, pieceLength: Int64?) async throws(UmbraError) -> Preview {
    let body = Operations.previewCreation.Input.Body.jsonPayload(
      path: path, pieceLength: pieceLength)
    let output = try await callUmbra { try await client.previewCreation(body: .json(body)) }
    guard case .ok(let ok) = output, case .json(let preview) = ok.body else {
      throw .unexpectedAnswer
    }
    return preview
  }

  /// Queues the torrent. Umbra reads the files in the background, one
  /// torrent at a time; the answer is the queued record.
  public func create(_ request: Components.Schemas.CreateTorrent) async throws(UmbraError)
    -> Creation
  {
    let output = try await callUmbra { try await client.createTorrent(body: .json(request)) }
    guard case .created(let made) = output, case .json(let creation) = made.body else {
      throw .unexpectedAnswer
    }
    return creation
  }

  /// Cancels a torrent being made, or dismisses a made one (a torrent that
  /// is seeding stays in the list).
  public func remove(_ id: String) async throws(UmbraError) {
    let output = try await callUmbra { try await client.removeCreation(path: .init(id: id)) }
    guard case .noContent = output else { throw .unexpectedAnswer }
  }

  /// The made torrent's .torrent file.
  public func torrentFile(_ id: String) async throws(UmbraError) -> Data {
    try await callUmbra {
      let output = try await client.downloadCreation(path: .init(id: id))
      guard case .ok(let ok) = output, case .application_x_hyphen_bittorrent(let body) = ok.body
      else { throw UmbraError.unexpectedAnswer }
      // A .torrent file is small next to what it describes; 256 MB is far
      // more than any real one.
      return try await Data(collecting: body, upTo: 256 << 20)
    }
  }
}
