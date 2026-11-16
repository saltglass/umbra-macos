import Foundation
import HTTPTypes
import OpenAPIRuntime

@testable import UmbraKit

/// A stand-in for the network for the Add sheet. Like `ScriptedTransport`,
/// but it can hold back the answer to any request whose path or body
/// contains some text until the test lets it go (a slow answer), and an
/// operation can have a list of answers given one after another (the last
/// one repeats).
actor GatedTransport: ClientTransport {
  private(set) var sent: [RecordingTransport.Sent] = []
  private var replies: [String: [RecordingTransport.Reply]]
  private var held: Set<String> = []

  init(_ replies: [String: [RecordingTransport.Reply]] = [:]) { self.replies = replies }

  func set(_ operation: String, _ answers: RecordingTransport.Reply...) {
    replies[operation] = answers
  }

  /// Holds back answers to requests that mention `text`.
  func hold(_ text: String) { held.insert(text) }
  func release(_ text: String) { held.remove(text) }

  func count(_ operation: String) -> Int { sent.filter { $0.operation == operation }.count }
  func sent(_ operation: String) -> [RecordingTransport.Sent] {
    sent.filter { $0.operation == operation }
  }

  func send(
    _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String
  ) async throws -> (HTTPResponse, HTTPBody?) {
    var text = ""
    if let body { text = try await String(collecting: body, upTo: 1 << 20) }
    let path = request.path ?? ""
    sent.append(.init(operation: operationID, method: request.method, path: path, body: text))
    // The answer is picked in the order requests are sent, even when one
    // is held back and answered later.
    var queue = replies[operationID] ?? []
    let reply = queue.first ?? .init()
    if queue.count > 1 {
      queue.removeFirst()
      replies[operationID] = queue
    }
    while held.contains(where: { text.contains($0) || path.contains($0) }) {
      try await Task.sleep(for: .milliseconds(2))
    }
    var response = HTTPResponse(status: reply.status)
    guard !reply.body.isEmpty else { return (response, nil) }
    response.headerFields[.contentType] = reply.contentType
    return (response, HTTPBody(reply.body))
  }
}

/// Made-up answers from Umbra about torrents to add. Hashes are made up;
/// no tracker or address in them is ever contacted.
enum AddSample {
  static let fileHash = String(repeating: "f", count: 40)
  static let magnetHash = String(repeating: "a", count: 40)
  static let otherHash = String(repeating: "b", count: 40)
  static let magnet = "magnet:?xt=urn:btih:\(magnetHash)&dn=Some.Thing"
  static let otherMagnet = "magnet:?xt=urn:btih:\(otherHash)&dn=Other"
  static let fileBytes = Data("d4:infod4:name4:test".utf8)

  /// A .torrent file of three files in a folder.
  static let torrentPreview = RecordingTransport.Reply.json(
    """
    {"hash":"\(fileHash)","name":"Sample.Set","detailsKnown":true,"size":600,"private":false,
     "trackers":["udp://tracker.invalid/a","udp://tracker.invalid/b"],
     "files":[{"path":"Sample.Set/b.bin","size":200},{"path":"Sample.Set/a.bin","size":100},
              {"path":"Sample.Set/sub/c.bin","size":300}]}
    """)

  static func waiting(_ hash: String = magnetHash, name: String = "Some.Thing", peers: Int = 3)
    -> RecordingTransport.Reply
  {
    .json(
      """
      {"hash":"\(hash)","name":"\(name)","detailsKnown":false,"private":false,"trackers":[],
       "waiting":true,"peers":\(peers)}
      """)
  }

  static let magnetDetails = RecordingTransport.Reply.json(
    """
    {"hash":"\(magnetHash)","name":"Some.Thing","detailsKnown":true,"size":50,"private":false,
     "trackers":[],"waiting":true,"files":[{"path":"Some.Thing.iso","size":50}]}
    """)

  static let duplicate = RecordingTransport.Reply.json(
    """
    {"hash":"\(fileHash)","name":"Sample.Set","detailsKnown":true,"size":600,"private":false,
     "trackers":["udp://tracker.invalid/a","udp://tracker.invalid/b"],
     "existing":{"hash":"\(fileHash)","name":"Sample.Set","state":"seeding",
                 "newTrackers":["udp://tracker.invalid/b"]}}
    """)

  static func added(_ hash: String = fileHash, already: Bool = false) -> RecordingTransport.Reply {
    .json(#"{"hash":"\#(hash)","alreadyAdded":\#(already)}"#)
  }

  static let folders = RecordingTransport.Reply.json(
    """
    {"folder":"","defaultFolder":"/data/downloads","incompleteFolder":"",
     "categories":[{"name":"films","folder":"/data/films"},{"name":"books","folder":""}]}
    """)

  static let badFile = RecordingTransport.Reply(
    status: .unprocessableContent,
    body:
      #"{"code":"invalid","message":"Some fields are invalid.","fields":{"torrentFile":"This isn't a .torrent file."}}"#
  )
}

extension RecordingTransport.Sent {
  /// The body's base64 .torrent file, decoded.
  var torrentFileBytes: Data? {
    (json?["torrentFile"] as? String).flatMap { Data(base64Encoded: $0) }
  }
}
