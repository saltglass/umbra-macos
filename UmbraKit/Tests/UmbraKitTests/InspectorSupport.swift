import Foundation
import HTTPTypes
import OpenAPIRuntime
import UmbraAPI

@testable import UmbraKit

/// Like `RecordingTransport`, but its answers can be changed while a test
/// runs (a fetch that works, then one that fails).
actor ScriptedTransport: ClientTransport {
  private(set) var sent: [RecordingTransport.Sent] = []
  private var replies: [String: RecordingTransport.Reply]

  init(_ replies: [String: RecordingTransport.Reply] = [:]) { self.replies = replies }

  func set(_ operation: String, _ reply: RecordingTransport.Reply) { replies[operation] = reply }

  /// How many requests for this operation have been sent.
  func count(_ operation: String) -> Int { sent.filter { $0.operation == operation }.count }

  func send(
    _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String
  ) async throws -> (HTTPResponse, HTTPBody?) {
    var text = ""
    if let body { text = try await String(collecting: body, upTo: 1 << 20) }
    sent.append(
      .init(operation: operationID, method: request.method, path: request.path ?? "", body: text))
    let reply = replies[operationID] ?? .init()
    var response = HTTPResponse(status: reply.status)
    guard !reply.body.isEmpty else { return (response, nil) }
    response.headerFields[.contentType] = reply.contentType
    return (response, HTTPBody(reply.body))
  }
}

/// A stand-in for waiting between fetches: it notes how long each wait
/// was asked to be, and only ends when the test says (`allow`).
actor TestSleeper {
  private(set) var durations: [Duration] = []
  private var allowed = 0

  func allow(_ times: Int = 1) { allowed += times }

  func sleep(_ duration: Duration) async throws {
    durations.append(duration)
    while allowed == 0 {
      // Throws when the task is cancelled, which is how a wait ends early.
      try await Task.sleep(for: .milliseconds(2))
    }
    allowed -= 1
  }
}

/// Waits (briefly) until something becomes true; false if it never does.
@MainActor
func eventually(_ condition: @MainActor () async -> Bool) async -> Bool {
  for _ in 0..<500 {
    if await condition() { return true }
    try? await Task.sleep(for: .milliseconds(4))
  }
  return false
}

// MARK: Sample answers

enum Sample {
  static let trackers = RecordingTransport.Reply.json(
    """
    {"dht":true,"pex":false,"trackers":[
      {"url":"udp://t.example/a","tier":0,"state":"working","seeds":5,"peers":1},
      {"url":"https://t.example/b","tier":1,"state":"error","message":"Unregistered torrent"}]}
    """)
  static let peers = RecordingTransport.Reply.json(
    """
    {"peers":[
      {"address":"192.0.2.1:1","client":"A 1.0","encrypted":true,"incoming":false,"progress":0.5,"downSpeed":10,"upSpeed":0},
      {"address":"192.0.2.2:2","encrypted":false,"incoming":true,"progress":1,"downSpeed":900,"upSpeed":5}]}
    """)
  static let files = RecordingTransport.Reply.json(
    """
    {"files":[
      {"index":0,"path":"Show/a.mkv","size":1000,"done":500,"priority":"normal"},
      {"index":1,"path":"Show/b.mkv","size":3000,"done":0,"priority":"skip"},
      {"index":2,"path":"Show/sub/c.srt","size":10,"done":10,"priority":"high"}]}
    """)
  static let noFiles = RecordingTransport.Reply.json(#"{"files":[]}"#)
  static let gone = RecordingTransport.Reply.error(
    .notFound, code: "torrent_not_found", message: "Umbra has no torrent with that hash.")

  /// A file as the API gives it.
  static func file(
    _ index: Int, _ path: String, size: Int64 = 100, done: Int64 = 0,
    _ priority: Components.Schemas.FilePriority = .normal
  ) -> Components.Schemas.TorrentFile {
    .init(index: index, path: path, size: size, done: done, priority: priority)
  }
}
