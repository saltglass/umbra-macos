import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import UmbraAPI

/// The two plain requests the Logs window makes (the stream is
/// `LogStreamClient`): the recent lines, and the file to save.
struct LogsService: Sendable {
  /// The most a saved file is read (5,000 lines are far smaller).
  static let downloadLimit = 32 << 20

  private let client: Client

  init(connection: Connection, transport: any ClientTransport) {
    client = connection.makeClient(
      transport: transport, extraMiddlewares: [ServerErrorMiddleware()])
  }

  /// The newest `limit` lines Umbra has kept, oldest first (GET /logs).
  func recent(limit: Int) async throws(UmbraError) -> Components.Schemas.LogPage {
    let output = try await callUmbra { try await client.getLogs(query: .init(limit: limit)) }
    guard case .ok(let ok) = output, case .json(let page) = ok.body else {
      throw .unexpectedAnswer
    }
    return page
  }

  /// The kept lines as Umbra's text file (GET /logs/download).
  func download(levels: String?, search: String?) async throws(UmbraError) -> Data {
    try await callUmbra {
      let output = try await client.downloadLogs(
        query: .init(levels: levels, q: search))
      guard case .ok(let ok) = output, case .plainText(let body) = ok.body else {
        throw UmbraError.unexpectedAnswer
      }
      return try await Data(collecting: body, upTo: Self.downloadLimit)
    }
  }
}
