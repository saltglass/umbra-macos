import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Carries the exact JSON for "set torrents' limits" to the request.
///
/// The generated request type can't write `null`, which is how a seed goal
/// is sent back to following its category. So the call hands the JSON it
/// wants through this task-local value, and the middleware puts it in the
/// request in place of the generated body (same path, headers and
/// credential; only the body bytes differ).
enum LimitsBody {
  @TaskLocal static var json: Data?
}

struct LimitsBodyMiddleware: ClientMiddleware {
  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String,
    next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
  ) async throws -> (HTTPResponse, HTTPBody?) {
    guard operationID == "setTorrentsLimits", let json = LimitsBody.json else {
      return try await next(request, body, baseURL)
    }
    return try await next(request, HTTPBody(json), baseURL)
  }
}
