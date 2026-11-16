import Foundation
import Testing

@testable import UmbraKit

/// Sorting what arrives from outside the app, and holding it until the Add
/// sheet can open.
@Suite struct IncomingItemsTests {
  static let magnet = "magnet:?xt=urn:btih:" + String(repeating: "a", count: 40) + "&dn=Sample"
  static let magnet2 = "magnet:?xt=urn:btih:" + String(repeating: "b", count: 40)

  func file(_ name: String) -> URL { URL(filePath: "/Users/someone/Downloads/\(name)") }

  // MARK: Sorting

  @Test func aTorrentFileIsAFile() {
    let url = file("sample.torrent")
    #expect(IncomingItems.classify(url) == .torrentFile(url))
  }

  @Test func aCapitalEndingIsStillATorrentFile() {
    let url = file("SAMPLE.TORRENT")
    #expect(IncomingItems.classify(url) == .torrentFile(url))
  }

  @Test func aMagnetLinkIsAMagnet() throws {
    let url = try #require(URL(string: Self.magnet))
    #expect(IncomingItems.classify(url) == .magnet(Self.magnet))
  }

  @Test func webAddressesAreIgnored() throws {
    #expect(
      IncomingItems.classify(try #require(URL(string: "http://example.com/a.torrent"))) == nil)
    #expect(
      IncomingItems.classify(try #require(URL(string: "https://example.com/a.torrent"))) == nil)
  }

  @Test func otherFilesAreIgnored() {
    #expect(IncomingItems.classify(file("notes.txt")) == nil)
    #expect(IncomingItems.classify(file("sample.torrent.zip")) == nil)
    #expect(IncomingItems.classify(file("torrent")) == nil)
  }

  @Test func junkIsIgnored() throws {
    #expect(IncomingItems.classify(try #require(URL(string: "ftp://example.com/x"))) == nil)
    // A magnet address with nothing in it is not a link Umbra could use.
    #expect(IncomingItems.classify(try #require(URL(string: "magnet:"))) == nil)
    #expect(IncomingItems.classify(text: "hello there") == [])
    #expect(IncomingItems.classify(text: "") == [])
    #expect(IncomingItems.classify(text: "https://example.com/a.torrent") == [])
  }

  @Test func droppedTextCanHoldMagnetsAndFileAddresses() {
    let text =
      "\(Self.magnet)\nnot a link\n file:///tmp/a.torrent \nfile:///tmp/b.txt\n\(Self.magnet2)"
    #expect(
      IncomingItems.classify(text: text) == [
        .magnet(Self.magnet), .torrentFile(URL(string: "file:///tmp/a.torrent")!),
        .magnet(Self.magnet2),
      ])
  }

  // MARK: Holding

  @Test func ignoredThingsAreNotKept() throws {
    var queue = IncomingItems()
    let kept = queue.add(urls: [file("a.txt"), try #require(URL(string: "https://x.test/a"))])
    #expect(!kept)
    #expect(queue.isEmpty)
    #expect(queue.nextBatch(ready: true) == nil)
  }

  @Test func arrivalsBeforeReadyAreHeldThenDeliveredAsOneBatch() {
    var queue = IncomingItems()
    let first = queue.add(urls: [file("a.torrent")])
    let second = queue.add(urls: [file("b.torrent")])
    #expect(first && second)
    #expect(queue.nextBatch(ready: false) == nil)
    #expect(queue.nextBatch(ready: false) == nil)
    #expect(queue.nextBatch(ready: true) == .files([file("a.torrent"), file("b.torrent")]))
    #expect(queue.nextBatch(ready: true) == nil)
    #expect(queue.isEmpty)
  }

  @Test func arrivalsWhileASheetIsOpenWaitForIt() {
    var queue = IncomingItems()
    // The sheet is open, so not ready; the new arrival waits.
    queue.add(urls: [file("late.torrent")])
    #expect(queue.nextBatch(ready: false) == nil)
    #expect(!queue.isEmpty)
    // The sheet closes.
    #expect(queue.nextBatch(ready: true) == .files([file("late.torrent")]))
  }

  @Test func aFileAlreadyWaitingIsNotKeptTwice() {
    var queue = IncomingItems()
    queue.add(urls: [file("a.torrent"), file("a.torrent")])
    queue.add(urls: [file("a.torrent")])
    #expect(queue.nextBatch(ready: true) == .files([file("a.torrent")]))
  }

  @Test func filesAndMagnetsComeOneSheetAfterAnotherFilesFirst() throws {
    var queue = IncomingItems()
    // The magnet arrives first, then files, then another magnet.
    queue.add(urls: [try #require(URL(string: Self.magnet))])
    queue.add(urls: [file("a.torrent")])
    queue.add(text: Self.magnet2)
    queue.add(urls: [file("b.torrent")])
    #expect(queue.nextBatch(ready: true) == .files([file("a.torrent"), file("b.torrent")]))
    #expect(queue.nextBatch(ready: true) == .magnet(Self.magnet))
    #expect(queue.nextBatch(ready: true) == .magnet(Self.magnet2))
    #expect(queue.nextBatch(ready: true) == nil)
  }

  @Test func theSameMagnetTwiceIsKeptOnce() throws {
    var queue = IncomingItems()
    queue.add(urls: [try #require(URL(string: Self.magnet))])
    queue.add(text: Self.magnet)
    #expect(queue.nextBatch(ready: true) == .magnet(Self.magnet))
    #expect(queue.nextBatch(ready: true) == nil)
  }

  @Test func somethingArrivingAfterADeliveryIsDeliveredToo() {
    var queue = IncomingItems()
    queue.add(urls: [file("a.torrent")])
    #expect(queue.nextBatch(ready: true) == .files([file("a.torrent")]))
    queue.add(urls: [file("b.torrent")])
    #expect(queue.nextBatch(ready: true) == .files([file("b.torrent")]))
  }
}
