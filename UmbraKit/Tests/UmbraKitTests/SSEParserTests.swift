import Testing

@testable import UmbraKit

@Suite struct SSEParserTests {
  /// Feeds the text through the parser one piece at a time.
  func parse(_ pieces: [[UInt8]]) -> [ServerSentEvent] {
    var parser = SSEParser()
    return pieces.flatMap { parser.push($0) }
  }

  @Test func readsEventNameAndData() {
    var parser = SSEParser()
    let events = parser.push("event: transfer\ndata: {\"a\":1}\n\n")
    #expect(events == [ServerSentEvent(type: "transfer", data: #"{"a":1}"#)])
  }

  @Test func joinsSeveralDataLinesWithLineBreaks() {
    var parser = SSEParser()
    let events = parser.push("data: one\ndata: two\ndata:\ndata: three\n\n")
    #expect(events.map(\.data) == ["one\ntwo\n\nthree"])
  }

  @Test func typeIsMessageWhenNoEventLine() {
    var parser = SSEParser()
    #expect(parser.push("data: x\n\n").map(\.type) == ["message"])
  }

  @Test func eventNameDoesNotCarryOverToTheNextMessage() {
    var parser = SSEParser()
    let events = parser.push("event: a\ndata: 1\n\ndata: 2\n\n")
    #expect(events.map(\.type) == ["a", "message"])
  }

  @Test func ignoresCommentLines() {
    var parser = SSEParser()
    let events = parser.push(": keep-alive\n\n:another\nevent: e\n: in the middle\ndata: d\n\n")
    #expect(events == [ServerSentEvent(type: "e", data: "d")])
  }

  @Test func messageWithNoDataIsNotDelivered() {
    var parser = SSEParser()
    #expect(parser.push("event: lonely\n\ndata: x\n\n").map(\.type) == ["message"])
  }

  @Test func readsIdAndKeepsItForLaterMessages() {
    var parser = SSEParser()
    let events = parser.push("id: 7\ndata: a\n\ndata: b\n\nid\ndata: c\n\n")
    #expect(events.map(\.lastEventID) == ["7", "7", ""])
  }

  @Test func idWithANullCharacterIsIgnored() {
    var parser = SSEParser()
    let events = parser.push("id: 1\ndata: a\n\nid: 2\u{0}x\ndata: b\n\n")
    #expect(events.map(\.lastEventID) == ["1", "1"])
  }

  @Test func readsRetryOnlyWhenItIsAllDigits() {
    var parser = SSEParser()
    _ = parser.push("retry: 5000\n\n")
    #expect(parser.reconnectionTime == 5000)
    _ = parser.push("retry: 12x\n\nretry:\n\n")
    #expect(parser.reconnectionTime == 5000)
  }

  @Test func removesOnlyOneSpaceAfterTheColon() {
    var parser = SSEParser()
    #expect(parser.push("data:  two spaces\ndata:none\n\n").map(\.data) == [" two spaces\nnone"])
  }

  @Test func lineWithNoColonIsAFieldWithAnEmptyValue() {
    var parser = SSEParser()
    #expect(parser.push("data\ndata\n\n").map(\.data) == ["\n"])
  }

  @Test func acceptsCRLFAndBareCRLineEnds() {
    var parser = SSEParser()
    let events = parser.push("event: a\r\ndata: 1\r\n\r\nevent: b\rdata: 2\r\rdata: 3\n\n")
    #expect(events.map(\.type) == ["a", "b", "message"])
    #expect(events.map(\.data) == ["1", "2", "3"])
  }

  @Test func crlfSplitBetweenPiecesIsOneLineEnd() {
    let events = parse([
      Array("data: a\r".utf8), Array("\n\r".utf8), Array("\ndata: b\r\n\r\n".utf8),
    ])
    #expect(events.map(\.data) == ["a", "b"])
  }

  @Test func piecesCutAnywhereGiveTheSameMessages() {
    let text =
      "retry: 5000\n\nevent: torrents.delta\ndata: {\"name\":\"Été ☃️ 🎬\"}\r\n\r\n"
      + ": keep-alive\n\nevent: transfer\ndata: 1\ndata: 2\n\n"
    let bytes = Array(text.utf8)
    var whole = SSEParser()
    let expected = whole.push(bytes)
    #expect(expected.count == 2)
    #expect(expected[0].data == #"{"name":"Été ☃️ 🎬"}"#)

    // One byte at a time: cuts every line and every multi-byte character.
    #expect(parse(bytes.map { [$0] }) == expected)
    // Every possible single cut, and some uneven piece sizes.
    for cut in 0...bytes.count {
      #expect(parse([Array(bytes[..<cut]), Array(bytes[cut...])]) == expected)
    }
    for size in [2, 3, 5, 7] {
      let pieces = stride(from: 0, to: bytes.count, by: size).map {
        Array(bytes[$0..<min($0 + size, bytes.count)])
      }
      #expect(parse(pieces) == expected)
    }
  }

  @Test func characterCutInHalfIsNotDecodedEarly() {
    // "é" is two bytes (C3 A9); the message isn't finished until the blank line.
    var parser = SSEParser()
    #expect(parser.push([0x64, 0x61, 0x74, 0x61, 0x3A, 0x20, 0xC3]).isEmpty)
    #expect(parser.push([0xA9, 0x0A, 0x0A]).map(\.data) == ["é"])
  }

  @Test func unfinishedMessageWaitsForItsBlankLine() {
    var parser = SSEParser()
    #expect(parser.push("event: a\ndata: x\n").isEmpty)
    #expect(parser.push("\n").map(\.type) == ["a"])
  }

  @Test func ignoresAByteOrderMarkAtTheStart() {
    var parser = SSEParser()
    #expect(parser.push([0xEF, 0xBB]).isEmpty)
    #expect(parser.push(Array("\u{FEFF}".utf8).dropFirst(2) + Array("data: x\n\n".utf8)).count == 1)
  }

  @Test func ignoresUnknownFields() {
    var parser = SSEParser()
    #expect(parser.push("foo: bar\ndata: x\n\n") == [ServerSentEvent(type: "message", data: "x")])
  }
}
