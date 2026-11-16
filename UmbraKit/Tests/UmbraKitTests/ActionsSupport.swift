import Foundation
import HTTPTypes
import OpenAPIRuntime

/// A stand-in for the network that notes each request (operation, method,
/// path and body) and answers from a list of canned replies by operation.
actor RecordingTransport: ClientTransport {
  struct Sent: Sendable {
    let operation: String
    let method: HTTPRequest.Method
    let path: String
    let body: String

    /// The body read as JSON, for comparing without caring about key order.
    var json: NSDictionary? {
      (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? NSDictionary
    }
  }

  struct Reply: Sendable {
    var status: HTTPResponse.Status = .noContent
    var contentType = "application/json"
    var body = ""
  }

  private(set) var sent: [Sent] = []
  private let replies: [String: Reply]

  /// - Parameter replies: the answer to each operation; any other gets "204 No Content".
  init(_ replies: [String: Reply] = [:]) {
    self.replies = replies
  }

  func send(
    _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String
  ) async throws -> (HTTPResponse, HTTPBody?) {
    var text = ""
    if let body { text = try await String(collecting: body, upTo: 1 << 20) }
    sent.append(
      Sent(operation: operationID, method: request.method, path: request.path ?? "", body: text))
    let reply = replies[operationID] ?? Reply()
    var response = HTTPResponse(status: reply.status)
    guard !reply.body.isEmpty else { return (response, nil) }
    response.headerFields[.contentType] = reply.contentType
    return (response, HTTPBody(reply.body))
  }
}

extension RecordingTransport.Reply {
  static func json(_ body: String, status: HTTPResponse.Status = .ok) -> Self {
    .init(status: status, body: body)
  }

  /// Umbra's error note, as it sends one.
  static func error(_ status: HTTPResponse.Status, code: String, message: String) -> Self {
    .init(status: status, body: #"{"code":"\#(code)","message":"\#(message)"}"#)
  }
}
