import Foundation
import Testing
import UmbraAPI

@testable import UmbraKit

/// The development stress feed: repeatable, varied, and readable by the real feed code.
@Suite struct StressFeedTests {
  let start = Date(timeIntervalSince1970: 1_793_000_000)

  @Test func theSameSeedGivesTheSameListAndChanges() {
    var one = StressFeed(seed: 7, start: start)
    var two = StressFeed(seed: 7, start: start)
    #expect(one.snapshot == two.snapshot)
    for _ in 0..<50 { #expect(one.step() == two.step()) }
    #expect(one.torrents == two.torrents)
  }

  @Test func anotherSeedGivesAnotherList() {
    #expect(
      StressFeed(seed: 1, start: start).torrents != StressFeed(seed: 2, start: start).torrents)
  }

  @Test func startsWithAHundredVariedTorrents() {
    let feed = StressFeed(start: start)
    #expect(feed.torrents.count == 100)
    #expect(Set(feed.torrents.map(\.hash)).count == 100)
    #expect(Set(feed.torrents.map(\.name)).count == 100)
    #expect(feed.torrents.allSatisfy { $0.hash.count == 40 })
    let states = Set(feed.torrents.map(\.state))
    #expect(states.count >= 8, "only \(states)")
    #expect(Set(feed.torrents.map(\.category)).count >= 3)
    #expect(Set(feed.torrents.compactMap(\.tracker)).count >= 4)
    #expect(feed.torrents.contains { !$0.tags.isEmpty })
    // Every row is one the list can show without surprises.
    for t in feed.torrents {
      #expect((0...1).contains(t.progress))
      #expect(t.addedAt <= start)
    }
  }

  @Test func eachSecondChangesAboutThirty() {
    var feed = StressFeed(start: start)
    var adds = 0
    var removes = 0
    var finishes = 0
    for _ in 0..<300 {
      let before = Dictionary(uniqueKeysWithValues: feed.torrents.map { ($0.hash, $0) })
      let delta = feed.step()
      #expect(delta.rev == delta.from + 1)
      #expect((25...36).contains(delta.changed.count + delta.removed.count))
      adds += delta.changed.filter { before[$0.hash] == nil }.count
      removes += delta.removed.count
      finishes +=
        delta.changed.filter { $0.state == .seeding && before[$0.hash]?.state == .downloading }
        .count
      #expect((85...115).contains(feed.torrents.count))
    }
    // Over five minutes, torrents come, go and finish.
    #expect(adds > 0)
    #expect(removes > 0)
    #expect(finishes > 0)
  }

  @Test func playsThroughTheRealFeedCode() async throws {
    let source = StressByteSource(feed: StressFeed(seed: 3, start: start), sleep: { _ in })
    let client = FeedClient(connection: DevStress.connection, source: source)
    var state = FeedState()
    var deltas = 0
    var transfers = 0
    for try await update in client.updates() {
      guard case .event(let event) = update else { continue }
      #expect(state.apply(.event(event)) == [], "a delta didn't follow on")
      if case .delta = event { deltas += 1 }
      if case .transfer = event { transfers += 1 }
      if deltas == 20 { break }
    }
    // What was read is exactly what the generator made.
    var expected = StressFeed(seed: 3, start: start)
    for _ in 0..<20 { _ = expected.step() }
    #expect(state.loaded)
    #expect(state.rev == expected.rev)
    #expect(state.torrents == expected.torrents)
    #expect(transfers >= 20)
  }

  @Test func answersARefetchWithTheWholeList() async throws {
    let source = StressByteSource(feed: StressFeed(seed: 3, start: start), sleep: { _ in })
    let client = FeedClient(connection: DevStress.connection, source: source)
    let snapshot = try await client.fetchSnapshot()
    #expect(snapshot == StressFeed(seed: 3, start: start).snapshot)
  }

  @Test func isOnlyOnWhenAsked() {
    #expect(DevStress.source(from: [:]) == nil)
    #expect(DevStress.source(from: ["UMBRA_DEV_STRESS": "0"]) == nil)
    #expect(DevStress.source(from: ["UMBRA_DEV_STRESS": "1"]) != nil)
  }

  @Test func rowsBuildFromIt() {
    let rows = StressFeed(start: start).torrents.map { TorrentRow($0, now: start) }
    let counts = TorrentFilter.counts(for: rows)
    #expect(counts.status[.all] == 100)
    #expect(StatusFilter.allCases.dropFirst().allSatisfy { (counts.status[$0] ?? 0) > 0 })
  }
}
