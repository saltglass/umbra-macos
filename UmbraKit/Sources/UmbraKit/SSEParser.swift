/// One message from a Server-Sent Events stream.
///
/// Umbra's live feed (`GET /api/v1/events`) is a long text response made of
/// messages like this, separated by blank lines:
///
///     event: torrents.delta
///     data: {"from":4,"rev":5,...}
///
public struct ServerSentEvent: Sendable, Equatable {
  /// The `event:` line, or "message" when the server gave none (the standard's default).
  public var type: String
  /// Every `data:` line of the message, joined with line breaks.
  public var data: String
  /// The most recent `id:` the server sent (it carries over between messages).
  public var lastEventID: String

  public init(type: String, data: String, lastEventID: String = "") {
    self.type = type
    self.data = data
    self.lastEventID = lastEventID
  }
}

/// Turns the raw bytes of a Server-Sent Events stream into messages, following
/// the web standard (the same rules a browser's `EventSource` uses).
///
/// Bytes arrive from the network in pieces of any size, cut anywhere: in the
/// middle of a line, between the two halves of a "\r\n", or even inside a
/// multi-byte character such as "é". So this keeps the unfinished line to one
/// side and only reads a line once its end has arrived. Line ends are always
/// plain ASCII bytes, which never occur inside a multi-byte character, so a
/// finished line is always whole text.
///
/// It does no networking itself: hand it bytes with `push`, get messages back.
public struct SSEParser: Sendable {
  /// How long the server asked clients to wait before reconnecting
  /// (`retry:`, in milliseconds), if it said. Umbra sends 5000.
  public private(set) var reconnectionTime: Int?

  private var line: [UInt8] = []
  private var lastByteWasCR = false
  private var isFirstLine = true
  private var eventType = ""
  private var dataBuffer: [UInt8] = []
  private var lastEventID = ""

  private static let lf: UInt8 = 0x0A
  private static let cr: UInt8 = 0x0D
  private static let colon: UInt8 = 0x3A
  private static let space: UInt8 = 0x20
  private static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

  public init() {}

  /// Reads the next piece of the stream and returns every message it completed.
  public mutating func push(_ bytes: some Sequence<UInt8>) -> [ServerSentEvent] {
    var events: [ServerSentEvent] = []
    for byte in bytes {
      // A "\r\n" is one line end, even when the two bytes arrive separately.
      if lastByteWasCR {
        lastByteWasCR = false
        if byte == Self.lf { continue }
      }
      switch byte {
      case Self.lf:
        endLine(into: &events)
      case Self.cr:
        endLine(into: &events)
        lastByteWasCR = true
      default:
        line.append(byte)
      }
    }
    return events
  }

  /// Text form of `push`, handy in tests.
  public mutating func push(_ text: String) -> [ServerSentEvent] {
    push(Array(text.utf8))
  }

  private mutating func endLine(into events: inout [ServerSentEvent]) {
    var bytes = line[...]
    line.removeAll(keepingCapacity: true)
    // The standard allows one invisible "byte order mark" at the very start.
    if isFirstLine {
      isFirstLine = false
      if bytes.starts(with: Self.byteOrderMark) { bytes = bytes.dropFirst(3) }
    }

    // A blank line ends the message.
    if bytes.isEmpty {
      dispatch(into: &events)
      return
    }
    // Lines starting with ":" are comments; Umbra sends ": keep-alive" every
    // 25 seconds so proxies don't think the connection is idle.
    if bytes.first == Self.colon { return }

    let field: ArraySlice<UInt8>
    var value: ArraySlice<UInt8>
    if let colon = bytes.firstIndex(of: Self.colon) {
      field = bytes[..<colon]
      value = bytes[bytes.index(after: colon)...]
      if value.first == Self.space { value = value.dropFirst() }
    } else {
      // A line with no colon is a field name with an empty value.
      field = bytes
      value = []
    }

    switch String(decoding: field, as: UTF8.self) {
    case "event":
      eventType = String(decoding: value, as: UTF8.self)
    case "data":
      dataBuffer.append(contentsOf: value)
      dataBuffer.append(Self.lf)
    case "id":
      if !value.contains(0) { lastEventID = String(decoding: value, as: UTF8.self) }
    case "retry":
      if !value.isEmpty, value.allSatisfy({ (0x30...0x39).contains($0) }),
        let milliseconds = Int(String(decoding: value, as: UTF8.self))
      {
        reconnectionTime = milliseconds
      }
    default:
      break  // Unknown fields are ignored, as the standard says.
    }
  }

  private mutating func dispatch(into events: inout [ServerSentEvent]) {
    defer {
      eventType = ""
      dataBuffer.removeAll(keepingCapacity: true)
    }
    // A message with no data lines isn't delivered (the standard's rule).
    guard !dataBuffer.isEmpty else { return }
    dataBuffer.removeLast()  // the line break added after the last data line
    events.append(
      ServerSentEvent(
        type: eventType.isEmpty ? "message" : eventType,
        data: String(decoding: dataBuffer, as: UTF8.self),
        lastEventID: lastEventID
      )
    )
  }
}
