import Foundation
import Testing
import UmbraAPI

@testable import UmbraKit

@Suite("inspector rows") struct InspectorRowsTests {
  func tracker(
    _ state: Components.Schemas.Tracker.statePayload, tier: Int = 0, message: String? = nil,
    seeds: Int? = nil, peers: Int? = nil, next: Date? = nil
  ) -> TrackerRow {
    TrackerRow(
      .init(
        url: "udp://t.example/a", tier: tier, state: state, message: message, seeds: seeds,
        peers: peers, nextAnnounce: next), now: testNow)
  }

  @Test func aWorkingTrackerShowsItsSwarmAndNextAsk() {
    let row = tracker(.working, seeds: 1, peers: 12, next: testNow.addingTimeInterval(125))
    #expect(row.statusText == "Working")
    #expect(row.role == .green)
    #expect(row.swarmText == "1 seed · 12 peers")
    #expect(row.nextText == "Next ask in 2m")
    #expect(row.tierText == "Tier 1")
    #expect(row.message == nil)
  }

  @Test func aFailedTrackerKeepsItsOwnWordsInRed() {
    let row = tracker(.error, tier: 2, message: "Unregistered torrent")
    #expect(row.statusText == "Error")
    #expect(row.role == .red)
    #expect(row.message == "Unregistered torrent")
    #expect(row.tierText == "Tier 3")
    #expect(row.swarmText == nil)
    #expect(row.nextText == nil)
    #expect(tracker(.error, message: "").message == nil)
  }

  @Test func aTrackerNotAskedYetSaysSo() {
    let row = tracker(.notContacted)
    #expect(row.statusText == "Not contacted yet")
    #expect(row.role == .secondary)
  }

  @Test func aDueAskReadsNow() {
    #expect(tracker(.working, next: testNow.addingTimeInterval(-5)).nextText == "Next ask now")
  }

  @Test func peersAreBusiestFirstThenByAddress() {
    func peer(_ address: String, down: Int64, up: Int64, client: String? = "X")
      -> Components.Schemas.Peer
    {
      .init(
        address: address, client: client, encrypted: true, incoming: false, progress: 0.5,
        downSpeed: down, upSpeed: up)
    }
    let rows = PeerRow.rows([
      peer("b", down: 0, up: 0), peer("a", down: 0, up: 0), peer("c", down: 10, up: 5, client: nil),
      peer("d", down: 100, up: 0),
    ])
    #expect(rows.map(\.address) == ["d", "c", "a", "b"])
    #expect(rows[1].client == "Unknown client")
    #expect(rows[0].downText == "100 B/s")
    #expect(rows[0].upText == "0 B/s")
    #expect(rows[0].progressText == "50%")
    #expect(rows[0].encryptionText == "Encrypted")
    #expect(rows[0].encryptionRole == .green)
    #expect(rows[0].directionText == "Outgoing")
  }

  @Test func plainConnectionsAreOrange() {
    let row = PeerRow(
      .init(
        address: "a", encrypted: false, incoming: true, progress: 1, downSpeed: 0, upSpeed: 0))
    #expect(row.encryptionText == "Plain")
    #expect(row.encryptionRole == .orange)
    #expect(row.directionText == "Incoming")
  }

  @Test func noPeersSaysWhy() {
    #expect(PeerRow.emptyText(for: .paused) == "Not connected to any peers while it isn't running.")
    #expect(PeerRow.emptyText(for: .queued) == "Not connected to any peers while it isn't running.")
    #expect(PeerRow.emptyText(for: .downloading) == "No peers connected yet.")
    #expect(PeerRow.emptyText(for: nil) == "No peers connected yet.")
  }

  @Test func severalTorrentsAreSummed() {
    let rows = [
      listRow(
        torrent("a") {
          $0.size = 1 << 30
          $0.downSpeed = 1 << 20
        }),
      listRow(
        torrent("b") {
          $0.size = 1 << 30
          $0.upSpeed = 2048
        }),
      listRow(torrent("c") { $0.size = 0 }),
    ]
    let summary = SelectionSummary(rows)
    #expect(summary.count == 3)
    #expect(summary.title == "3 torrents selected")
    #expect(summary.detail == "2.0 GB total · ↓ 1.0 MB/s · ↑ 2 KB/s")
  }
}
