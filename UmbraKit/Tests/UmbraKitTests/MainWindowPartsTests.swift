import Foundation
import Testing
import UmbraAPI

@testable import UmbraKit

@Suite struct ListStepTests {
  func check(_ old: [String], _ new: [String], limit: Int = 60) -> [ListStep]? {
    let steps = ListStep.steps(from: old, to: new, limit: limit)
    if let steps { #expect(ListStep.apply(steps, to: old, taking: new) == new) }
    return steps
  }

  @Test func theSameListNeedsNothing() {
    #expect(check(["a", "b"], ["a", "b"]) == [])
  }

  @Test func removalsGoFirstInOneStep() {
    #expect(check(["a", "b", "c", "d"], ["a", "d"]) == [.remove([1, 2])])
  }

  @Test func insertsAndMoves() {
    #expect(check(["a", "b", "c"], ["n", "a", "b", "c"]) == [.insert(0)])
    #expect(check(["a", "b", "c", "d"], ["d", "a", "b", "c"]) == [.move(from: 3, to: 0)])
    #expect(check(["a", "b", "c"], ["c", "x", "a"]) != nil)
  }

  @Test func tooMuchChangeAsksForAFullRedraw() {
    let old = (0..<100).map(String.init)
    #expect(check(old, old.reversed(), limit: 10) == nil)
  }

  @Test func theViewStaysPutWhenRowsComeAndGoAbove() {
    let old = ["a", "b", "c", "d", "e", "f"]
    // At the top: stay there.
    #expect(ListStep.topRow(old: old, new: ["n"] + old, top: 0) == nil)
    // Nothing came or went: the same row number.
    #expect(ListStep.topRow(old: old, new: old, top: 3) == 3)
    // Two new rows above: two further down, so "d" stays on top.
    #expect(ListStep.topRow(old: old, new: ["n", "m"] + old, top: 3) == 5)
    // "a" went: one further up, "d" still on top.
    #expect(ListStep.topRow(old: old, new: Array(old.dropFirst()), top: 3) == 2)
    // Rows only swapped places (a speed sort): the view doesn't move.
    #expect(ListStep.topRow(old: old, new: ["d", "b", "c", "a", "e", "f"], top: 3) == 3)
    // A new row exactly at the top goes above the view.
    #expect(ListStep.topRow(old: old, new: ["a", "b", "c", "n", "d", "e", "f"], top: 3) == 4)
  }

  @Test func randomListsAlwaysComeOutRight() {
    var random = SeededRandom(seed: 7)
    for _ in 0..<300 {
      let pool = (0..<30).map { "h\($0)" }
      let old = pool.filter { _ in Bool.random(using: &random) }.shuffled(using: &random)
      let new = pool.filter { _ in Bool.random(using: &random) }.shuffled(using: &random)
      _ = check(old, new, limit: .max)
    }
  }
}

@Suite struct SidebarSectionTests {
  func rows(_ torrents: [Components.Schemas.Torrent]) -> TorrentCounts {
    TorrentCounts(torrents.map(listRow))
  }

  @Test func statusRowsAlwaysShowEvenEmpty() {
    let sections = SidebarSection.all(for: rows([]))
    #expect(sections.map(\.id) == ["status"])
    #expect(sections[0].title == nil)
    #expect(
      sections[0].items.map(\.title) == [
        "All Torrents", "Downloading", "Seeding", "Paused", "Queued", "Errors",
      ])
    #expect(sections[0].items.allSatisfy { $0.count == 0 && !$0.isAlert })
  }

  @Test func groupsShowWhenTheyHaveSomethingAndTrackersFromTwo() {
    let one = rows([
      torrent("a") {
        $0.category = "films"
        $0.tags = ["4k"]
        $0.tracker = "t.example"
      }
    ])
    #expect(SidebarSection.all(for: one).map(\.id) == ["status", "categories", "tags"])
    let two = rows([
      torrent("a") { $0.tracker = "one.example" },
      torrent("b") { $0.tracker = "two.example" },
    ])
    let sections = SidebarSection.all(for: two)
    #expect(sections.map(\.id) == ["status", "trackers"])
    #expect(sections[1].items.map(\.filter) == [.tracker("one.example"), .tracker("two.example")])
    #expect(sections[1].items.map(\.symbolName) == ["globe", "globe"])
  }

  @Test func errorsAreAnAlertOnlyWhenThereAreSome() {
    let sections = SidebarSection.all(for: rows([torrent("a") { $0.state = .error }]))
    let errors = sections[0].items.last!
    #expect(errors.filter == .status(.errors))
    #expect(errors.count == 1)
    #expect(errors.isAlert)
  }
}

@Suite struct StatusBarInfoTests {
  let english = Locale(identifier: "en_GB")

  @Test func readsTheFeedsTotals() {
    var t = transfer()
    t.freeSpace = 412 << 30
    t.dhtNodes = 1204
    t.downSpeed = 0
    t.upSpeed = 2048
    t.sessionDownloaded = 31 << 30
    let info = StatusBarInfo(
      transfer: t, connection: .live, listenPort: 6881, vpn: nil, locale: english)
    #expect(info.freeSpace == "412 GB free")
    #expect(info.incomingWorks)
    #expect(info.incoming == "Incoming connections: working")
    #expect(info.port == "Port 6881")
    #expect(info.dht == "DHT: 1,204 nodes")
    #expect(info.down == "0 B/s")
    #expect(info.up == "2 KB/s")
    #expect(info.session == "This session: 31.0 GB down, 0 B up")
    #expect(info.feedNote == nil)
  }

  @Test func beforeTheFirstTotals() {
    let info = StatusBarInfo(
      transfer: nil, connection: .connecting, listenPort: nil, vpn: nil, locale: english)
    #expect(info.freeSpace == nil)
    #expect(!info.incomingWorks)
    #expect(info.incoming == "No incoming connections yet")
    #expect(info.port == nil)
    #expect(info.dht == "DHT: —")
    #expect(info.feedNote == "Connecting…")
  }

  @Test func aConnectedVPNsForwardedPortIsThePeersPort() {
    var vpn = Components.Schemas.VpnStatus(
      state: .connected, configured: true, saved: [],
      failover: .init(enabled: false, minutes: 5))
    vpn.forwardedPort = 51413
    #expect(StatusBarInfo.peerPort(listenPort: 6881, vpn: vpn) == 51413)
    vpn.state = .down
    #expect(StatusBarInfo.peerPort(listenPort: 6881, vpn: vpn) == 6881)
  }

  @Test func aNegativeFreeSpaceMeansUnknown() {
    var t = transfer()
    t.freeSpace = -1
    let info = StatusBarInfo(transfer: t, connection: .live, listenPort: nil, vpn: nil)
    #expect(info.freeSpace == nil)
  }
}
