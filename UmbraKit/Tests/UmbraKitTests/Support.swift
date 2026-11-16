import Foundation
import HTTPTypes
import OpenAPIRuntime

/// A stand-in for the network: remembers what was sent and answers with a canned reply.
actor FakeTransport: ClientTransport {
  private(set) var requests: [HTTPRequest] = []
  private let status: HTTPResponse.Status
  private let json: String

  init(status: HTTPResponse.Status = .noContent, json: String = "") {
    self.status = status
    self.json = json
  }

  func send(
    _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String
  ) async throws -> (HTTPResponse, HTTPBody?) {
    requests.append(request)
    var response = HTTPResponse(status: status)
    guard !json.isEmpty else { return (response, nil) }
    response.headerFields[.contentType] = "application/json"
    return (response, HTTPBody(json))
  }
}
