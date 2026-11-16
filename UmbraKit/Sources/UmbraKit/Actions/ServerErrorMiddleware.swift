import Foundation
import HTTPTypes
import OpenAPIRuntime
import UmbraAPI

/// Turns any answer from Umbra that isn't a success into an `UmbraError`
/// carrying the server's own plain-English message.
///
/// Umbra answers every failure with the same small note (`code`, `message`,
/// `fields`), but the generated client files each operation's failures
/// under a different Swift type. Reading the note here, once, for every
/// operation, saves unpicking those types call by call.
struct ServerErrorMiddleware: ClientMiddleware {
  /// The most of an error answer that is read (a note is far smaller).
  static let limit = 1 << 20

  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String,
    next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
  ) async throws -> (HTTPResponse, HTTPBody?) {
    let (response, responseBody) = try await next(request, body, baseURL)
    guard response.status.kind != .successful else { return (response, responseBody) }
    var data = Data()
    if let responseBody {
      data = (try? await Data(collecting: responseBody, upTo: Self.limit)) ?? Data()
    }
    if let note = try? JSONDecoder().decode(Components.Schemas._Error.self, from: data) {
      throw UmbraError(note)
    }
    throw UmbraError(
      code: "http_\(response.status.code)",
      message: "Umbra answered with an error it didn't explain (HTTP \(response.status.code)).")
  }
}

extension UmbraError {
  /// Umbra couldn't be reached at all (the request never got an answer).
  static func unreachable(_ error: any Error) -> UmbraError {
    UmbraError(
      code: "unreachable", message: "Umbra couldn't be reached: \(error.localizedDescription)")
  }

  /// Umbra answered, but not in a way this version of the app understands.
  static let unexpectedAnswer = UmbraError(
    code: "unexpected_answer",
    message: "Umbra gave an answer this version of the app doesn't understand.")
}

/// Runs one request through the generated client, turning whatever goes
/// wrong into an `UmbraError` (shared by `TorrentActions` and `SettingsActions`).
func callUmbra<T>(_ request: () async throws -> T) async throws(UmbraError) -> T {
  do {
    return try await request()
  } catch let error as UmbraError {
    throw error
  } catch let error as ClientError {
    // The generated client wraps what the middleware threw; unwrap it.
    if let note = error.underlyingError as? UmbraError { throw note }
    throw .unreachable(error.underlyingError)
  } catch {
    throw .unreachable(error)
  }
}
