import Foundation
import Testing
import UmbraAPI

@testable import UmbraKit

/// The rules for bringing the list up to date, as the web app's feed.ts has them.
@Suite struct FeedStateTests {
  func names(_ state: FeedState) -> [String] { state.torrents.map(\.name) }

  // Carried over from feed.test.ts: "skips a delta it already has and applies the next".
  // The server sends a new stream its snapshot, then the change that
  // snapshot took (to every stream), which is already in it.
  @Test func skipsADeltaItAlreadyHasAndAppliesTheNext() {
    var state = FeedState()
    #expect(state.apply(.event(snapshot(rev: 1, [row("a", "new")]))) == [])
    let skipped = state.apply(.event(delta(from: 0, rev: 1, changed: [row("a", "old")])))
    #expect(skipped == [])  // no refetch
    #expect(state.rev == 1)
    #expect(state.torrent(hash: "a")?.name == "new")

    #expect(state.apply(.event(delta(from: 1, rev: 2, changed: [row("a", "newer")]))) == [])
    #expect(state.rev == 2)
    #expect(state.torrent(hash: "a")?.name == "newer")
  }

  // feed.ts `delta`: `if (d.from !== this.state.rev) { refetch }`.
  @Test func deltaThatDoesNotFollowOnAsksForARefetchAndChangesNothing() {
    var state = FeedState()
    _ = state.apply(.event(snapshot(rev: 3, [row("a", "a")])))
    let before = state
    #expect(state.apply(.event(delta(from: 4, rev: 5, changed: [row("b", "b")]))) == [.refetch])
    #expect(state == before)
  }

  // feed.ts starts at rev 0 with an empty list, so a delta from 0 applies even before a snapshot.
  @Test func deltaFromZeroAppliesBeforeAnySnapshot() {
    var state = FeedState()
    #expect(state.apply(.event(delta(from: 0, rev: 1, changed: [row("a", "a")]))) == [])
    #expect(names(state) == ["a"])
    #expect(!state.loaded)
  }

  @Test func snapshotReplacesTheListAndMarksItLoaded() {
    var state = FeedState()
    _ = state.apply(.event(snapshot(rev: 2, [row("a", "a"), row("b", "b")])))
    #expect(state.loaded)
    _ = state.apply(.event(snapshot(rev: 9, [row("c", "c")])))
    #expect(names(state) == ["c"])
    #expect(state.rev == 9)
    #expect(state.torrent(hash: "a") == nil)
  }

  // A fresh snapshot (after a reconnect) may be at a lower rev, if Umbra restarted.
  @Test func snapshotIsTakenEvenAtALowerRev() {
    var state = FeedState()
    _ = state.apply(.event(snapshot(rev: 50, [row("a", "a")])))
    _ = state.apply(.event(snapshot(rev: 1, [row("b", "b")])))
    #expect(state.rev == 1)
    #expect(names(state) == ["b"])
  }

  // feed.ts keeps a Map: a changed torrent keeps its place, a new one goes at the end.
  @Test func changedTorrentsKeepTheirPlaceAndNewOnesGoAtTheEnd() {
    var state = FeedState()
    _ = state.apply(.event(snapshot(rev: 1, [row("a", "a"), row("b", "b"), row("c", "c")])))
    _ = state.apply(.event(delta(from: 1, rev: 2, changed: [row("d", "d"), row("b", "B")])))
    #expect(names(state) == ["a", "B", "c", "d"])
    #expect(state.torrent(hash: "d")?.name == "d")
  }

  @Test func removedTorrentsLeaveAndTheRestKeepTheirOrder() {
    var state = FeedState()
    _ = state.apply(.event(snapshot(rev: 1, [row("a", "a"), row("b", "b"), row("c", "c")])))
    _ = state.apply(.event(delta(from: 1, rev: 2, removed: ["b", "unknown"])))
    #expect(names(state) == ["a", "c"])
    #expect(state.torrent(hash: "b") == nil)
    #expect(state.torrent(hash: "c")?.name == "c")
    // Lookup still right after positions moved.
    _ = state.apply(.event(delta(from: 2, rev: 3, changed: [row("c", "C")])))
    #expect(names(state) == ["a", "C"])
  }

  // feed.ts sets the changed rows first, then deletes the removed ones.
  @Test func torrentBothChangedAndRemovedEndsUpRemoved() {
    var state = FeedState()
    _ = state.apply(.event(snapshot(rev: 1, [row("a", "a")])))
    _ = state.apply(.event(delta(from: 1, rev: 2, changed: [row("a", "x")], removed: ["a"])))
    #expect(state.torrents.isEmpty)
  }

  // new Map(list) keeps the first place and the last value of a repeated key.
  @Test func snapshotWithARepeatedHashKeepsOneRow() {
    var state = FeedState()
    _ = state.apply(.event(snapshot(rev: 1, [row("a", "1"), row("b", "b"), row("a", "2")])))
    #expect(names(state) == ["2", "b"])
  }

  // feed.ts `patch`: rows in at once, rev untouched.
  @Test func patchPutsRowsInWithoutChangingTheRevision() {
    var state = FeedState()
    _ = state.apply(.event(snapshot(rev: 4, [row("a", "a")])))
    state.patch([row("a", "A"), row("z", "z")])
    #expect(names(state) == ["A", "z"])
    #expect(state.rev == 4)
  }

  @Test func transferAndCreationsAreKept() {
    var state = FeedState()
    _ = state.apply(.event(.transfer(transfer(vpn: .held))))
    _ = state.apply(.event(.creations([])))
    #expect(state.transfer?.vpn == .held)
    #expect(state.creations == [])
  }

  @Test func finishedAndSettingsChangedAreHandedBack() {
    var state = FeedState()
    let finished = Components.Schemas.TorrentFinished(hash: "a", name: "A", size: 3)
    #expect(state.apply(.event(.finished(finished))) == [.finished(finished)])
    #expect(
      state.apply(.event(.settingsChanged(group: "security")))
        == [.settingsChanged(group: "security")])
  }

  // feed.ts: onopen → live, onerror → reconnecting.
  @Test func connectionStateFollowsOpenAndDrop() {
    var state = FeedState()
    #expect(state.connection == .connecting)
    _ = state.apply(.opened)
    #expect(state.connection == .live)
    let first = Date(timeIntervalSince1970: 100)
    _ = state.apply(.dropped(at: first))
    _ = state.apply(.dropped(at: Date(timeIntervalSince1970: 200)))
    #expect(state.connection == .reconnecting(since: first))
    _ = state.apply(.opened)
    #expect(state.connection == .live)
  }
}
