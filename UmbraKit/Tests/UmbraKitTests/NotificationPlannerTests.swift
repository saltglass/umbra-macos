import Foundation
import Testing
import UmbraAPI

@testable import UmbraKit

/// The rules for which notifications are sent, with made-up torrents.
@Suite struct NotificationPlannerTests {
  let start = Date(timeIntervalSince1970: 1_000_000)

  func torrent(
    _ hash: String, state: Components.Schemas.TorrentState = .downloading,
    progress: Double = 0.5, error: String? = nil
  ) -> Components.Schemas.Torrent {
    var t = row(hash, "Name \(hash)")
    t.state = state
    t.progress = progress
    t.error = error
    return t
  }

  func snap(
    _ torrents: [Components.Schemas.Torrent], at seconds: TimeInterval = 0,
    vpn: Components.Schemas.VpnState? = .connected,
    reason: Components.Schemas.VpnHeldReason? = nil, connected: Bool = true
  ) -> NotificationSnapshot {
    var t: Components.Schemas.Transfer?
    if let vpn {
      var made = transfer(vpn: vpn)
      made.vpnHeldReason = reason
      t = made
    }
    return NotificationSnapshot(
      torrents: torrents, transfer: t, connected: connected,
      now: start.addingTimeInterval(seconds))
  }

  // MARK: Finished

  @Test func finishedOnlyAfterBeingSeenDownloading() {
    var planner = NotificationPlanner()
    let on = NotificationSwitches()
    #expect(planner.plan(snap([torrent("a")]), switches: on).isEmpty)
    let done = planner.plan(
      snap([torrent("a", state: .seeding, progress: 1)], at: 1), switches: on)
    #expect(
      done == [
        PlannedNotification(
          kind: .finished, title: "Name a", body: "Download finished", torrentHash: "a")
      ])
  }

  @Test func nothingForTorrentsAlreadyCompleteAtFirstSnapshot() {
    var planner = NotificationPlanner()
    let on = NotificationSwitches()
    let list = [
      torrent("a", state: .seeding, progress: 1), torrent("b", state: .seeding, progress: 1),
    ]
    #expect(planner.plan(snap(list), switches: on).isEmpty)
    #expect(planner.plan(snap(list, at: 1), switches: on).isEmpty)
  }

  @Test func nothingForACompleteTorrentThatIsAddedLater() {
    var planner = NotificationPlanner()
    let on = NotificationSwitches()
    _ = planner.plan(snap([]), switches: on)
    let added = [torrent("a", state: .seeding, progress: 1)]
    #expect(planner.plan(snap(added, at: 1), switches: on).isEmpty)
  }

  @Test func nothingAfterARecheckOfACompleteTorrent() {
    var planner = NotificationPlanner()
    let on = NotificationSwitches()
    _ = planner.plan(snap([torrent("a", state: .seeding, progress: 1)]), switches: on)
    let checking = planner.plan(
      snap([torrent("a", state: .checking, progress: 0.4)], at: 1), switches: on)
    #expect(checking.isEmpty)
    let back = planner.plan(
      snap([torrent("a", state: .seeding, progress: 1)], at: 2), switches: on)
    #expect(back.isEmpty)
  }

  @Test func aFinishedTorrentIsAnnouncedOnlyOnceEvenAfterARecheck() {
    var planner = NotificationPlanner()
    let on = NotificationSwitches()
    _ = planner.plan(snap([torrent("a")]), switches: on)
    #expect(
      planner.plan(snap([torrent("a", state: .seeding, progress: 1)], at: 1), switches: on).count
        == 1)
    _ = planner.plan(snap([torrent("a", state: .checking, progress: 0.2)], at: 2), switches: on)
    #expect(
      planner.plan(snap([torrent("a", state: .seeding, progress: 1)], at: 3), switches: on)
        .isEmpty)
  }

  @Test func nothingWhileDisconnectedAndNoReplayAfterReconnecting() {
    var planner = NotificationPlanner()
    let on = NotificationSwitches()
    _ = planner.plan(snap([torrent("a")]), switches: on)
    #expect(planner.plan(snap([], at: 1, connected: false), switches: on).isEmpty)
    // The torrent finished while Umbra was away: nothing is replayed.
    let after = [torrent("a", state: .seeding, progress: 1)]
    #expect(planner.plan(snap(after, at: 2), switches: on).isEmpty)
    #expect(planner.plan(snap(after, at: 3), switches: on).isEmpty)
  }

  @Test func nothingIsSaidWhileDisconnectedEvenForNewNews() {
    var planner = NotificationPlanner()
    let on = NotificationSwitches()
    _ = planner.plan(snap([torrent("a")]), switches: on)
    let done = [torrent("a", state: .seeding, progress: 1)]
    #expect(planner.plan(snap(done, at: 1, connected: false), switches: on).isEmpty)
  }

  @Test func moreThanThreeFinishesInTenSecondsBecomeOneSummary() {
    var planner = NotificationPlanner()
    let on = NotificationSwitches()
    let hashes = ["a", "b", "c", "d"]
    _ = planner.plan(snap(hashes.map { torrent($0) }), switches: on)
    let done = hashes.map { torrent($0, state: .seeding, progress: 1) }
    let result = planner.plan(snap(done, at: 1), switches: on)
    #expect(result.count == 1)
    #expect(result.first?.title == "4 downloads finished")
    #expect(result.first?.torrentHash == nil)
  }

  @Test func threeFinishesAreSentOneByOne() {
    var planner = NotificationPlanner()
    let on = NotificationSwitches()
    let hashes = ["a", "b", "c"]
    _ = planner.plan(snap(hashes.map { torrent($0) }), switches: on)
    let done = hashes.map { torrent($0, state: .seeding, progress: 1) }
    #expect(planner.plan(snap(done, at: 1), switches: on).count == 3)
  }

  @Test func finishesSpreadOverTimeCountTogetherOnlyInsideTenSeconds() {
    var planner = NotificationPlanner()
    let on = NotificationSwitches()
    let hashes = ["a", "b", "c", "d"]
    var list = hashes.map { torrent($0) }
    _ = planner.plan(snap(list), switches: on)
    // Three at once, then a fourth 20 seconds later: that one stands alone.
    for index in 0..<3 { list[index] = torrent(hashes[index], state: .seeding, progress: 1) }
    #expect(planner.plan(snap(list, at: 1), switches: on).count == 3)
    list[3] = torrent("d", state: .seeding, progress: 1)
    let late = planner.plan(snap(list, at: 21), switches: on)
    #expect(late.map(\.title) == ["Name d"])
    // A fourth within 10 seconds of the three joins them in a summary.
    var quick = NotificationPlanner()
    var list2 = hashes.map { torrent($0) }
    _ = quick.plan(snap(list2), switches: on)
    for index in 0..<3 { list2[index] = torrent(hashes[index], state: .seeding, progress: 1) }
    _ = quick.plan(snap(list2, at: 1), switches: on)
    list2[3] = torrent("d", state: .seeding, progress: 1)
    #expect(quick.plan(snap(list2, at: 5), switches: on).map(\.title) == ["4 downloads finished"])
  }

  // MARK: Problems

  @Test func aProblemIsAnnouncedOncePerProblem() {
    var planner = NotificationPlanner()
    let on = NotificationSwitches()
    _ = planner.plan(snap([torrent("a")]), switches: on)
    let bad = torrent("a", state: .error, error: "The disk is full.")
    let first = planner.plan(snap([bad], at: 1), switches: on)
    #expect(
      first == [
        PlannedNotification(
          kind: .problem, title: "Name a", body: "The disk is full.", torrentHash: "a")
      ])
    // Updates that change nothing say nothing.
    #expect(planner.plan(snap([bad], at: 2), switches: on).isEmpty)
    #expect(planner.plan(snap([bad], at: 3), switches: on).isEmpty)
    // A different problem is news.
    let other = torrent("a", state: .error, error: "Permission denied.")
    #expect(planner.plan(snap([other], at: 4), switches: on).count == 1)
    // After it recovers, the same problem is news again.
    _ = planner.plan(snap([torrent("a")], at: 5), switches: on)
    #expect(planner.plan(snap([bad], at: 6), switches: on).count == 1)
  }

  @Test func aProblemAlreadyThereAtConnectIsNotAnnounced() {
    var planner = NotificationPlanner()
    let bad = torrent("a", state: .error, error: "The disk is full.")
    #expect(planner.plan(snap([bad]), switches: NotificationSwitches()).isEmpty)
    #expect(planner.plan(snap([bad], at: 1), switches: NotificationSwitches()).isEmpty)
  }

  @Test func aProblemWithoutWordsStillSaysSomething() {
    var planner = NotificationPlanner()
    let on = NotificationSwitches()
    _ = planner.plan(snap([torrent("a")]), switches: on)
    let result = planner.plan(snap([torrent("a", state: .error)], at: 1), switches: on)
    #expect(result.first?.body == "Something went wrong.")
  }

  // MARK: The VPN

  @Test func noVpnNoticeForTheFirstStateSeen() {
    var planner = NotificationPlanner()
    let on = NotificationSwitches()
    #expect(planner.plan(snap([], vpn: .down), switches: on).isEmpty)
    #expect(planner.plan(snap([], at: 1, vpn: .down), switches: on).isEmpty)
  }

  @Test func theTotalsArrivingAfterTheListStillCountAsTheFirstState() {
    var planner = NotificationPlanner()
    let on = NotificationSwitches()
    #expect(planner.plan(snap([], vpn: nil), switches: on).isEmpty)
    #expect(planner.plan(snap([], at: 1, vpn: .down), switches: on).isEmpty)
  }

  @Test func vpnDownThenUp() {
    var planner = NotificationPlanner()
    let on = NotificationSwitches()
    _ = planner.plan(snap([], vpn: .connected), switches: on)
    let down = planner.plan(snap([], at: 1, vpn: .down), switches: on)
    #expect(down.count == 1)
    #expect(down.first?.kind == .vpn)
    #expect(down.first?.title == "VPN down")
    let up = planner.plan(snap([], at: 100, vpn: .connected), switches: on)
    #expect(up.first?.title == "VPN connected again")
  }

  @Test func vpnHeldUsesTheHeldWords() {
    var planner = NotificationPlanner()
    let on = NotificationSwitches()
    _ = planner.plan(snap([], vpn: .connected), switches: on)
    let held = planner.plan(snap([], at: 1, vpn: .held, reason: .vpnRemoved), switches: on)
    let words = HeldWords(reason: .vpnRemoved)
    #expect(held.first?.title == words.title)
    #expect(held.first?.body == words.detail)
  }

  @Test func connectingAndNoVpnSayNothing() {
    var planner = NotificationPlanner()
    let on = NotificationSwitches()
    _ = planner.plan(snap([], vpn: .connected), switches: on)
    #expect(planner.plan(snap([], at: 1, vpn: .connecting), switches: on).isEmpty)
    #expect(planner.plan(snap([], at: 2, vpn: .none), switches: on).isEmpty)
  }

  @Test func noBackNoticeIfItWasNeverReportedDown() {
    var planner = NotificationPlanner()
    let on = NotificationSwitches()
    _ = planner.plan(snap([], vpn: .connecting), switches: on)
    #expect(planner.plan(snap([], at: 1, vpn: .connected), switches: on).isEmpty)
  }

  @Test func flappingIsCollapsedToOnePerThirtySecondsWithTheLatestState() {
    var planner = NotificationPlanner()
    let on = NotificationSwitches()
    _ = planner.plan(snap([], vpn: .connected), switches: on)
    #expect(planner.plan(snap([], at: 1, vpn: .down), switches: on).count == 1)
    // Back up and down again inside 30 seconds: nothing more is said.
    #expect(planner.plan(snap([], at: 5, vpn: .connected), switches: on).isEmpty)
    #expect(planner.plan(snap([], at: 10, vpn: .down), switches: on).isEmpty)
    #expect(planner.plan(snap([], at: 20, vpn: .connected), switches: on).isEmpty)
    // Once 30 seconds have passed, the state as it is now is reported.
    let later = planner.plan(snap([], at: 32, vpn: .connected), switches: on)
    #expect(later.map(\.title) == ["VPN connected again"])
    #expect(planner.plan(snap([], at: 33, vpn: .connected), switches: on).isEmpty)
  }

  @Test func aDownThatFlapsBackToTheReportedStateSaysNothingMore() {
    var planner = NotificationPlanner()
    let on = NotificationSwitches()
    _ = planner.plan(snap([], vpn: .connected), switches: on)
    _ = planner.plan(snap([], at: 1, vpn: .down), switches: on)
    _ = planner.plan(snap([], at: 5, vpn: .connected), switches: on)
    #expect(planner.plan(snap([], at: 40, vpn: .down), switches: on).isEmpty)
  }

  // MARK: Switches

  @Test func eachSwitchSilencesOnlyItsOwnKind() {
    func run(_ switches: NotificationSwitches) -> Set<NotificationKind> {
      var planner = NotificationPlanner()
      _ = planner.plan(snap([torrent("a"), torrent("b")], vpn: .connected), switches: switches)
      let next = [
        torrent("a", state: .seeding, progress: 1),
        torrent("b", state: .error, error: "Broken."),
      ]
      let result = planner.plan(snap(next, at: 1, vpn: .down), switches: switches)
      return Set(result.map(\.kind))
    }
    #expect(run(NotificationSwitches()) == [.finished, .problem, .vpn])
    #expect(run(NotificationSwitches(finished: false)) == [.problem, .vpn])
    #expect(run(NotificationSwitches(problem: false)) == [.finished, .vpn])
    #expect(run(NotificationSwitches(vpn: false)) == [.finished, .problem])
    #expect(run(NotificationSwitches(finished: false, problem: false, vpn: false)).isEmpty)
  }

  @Test func turningASwitchOnLaterDoesNotReplayOldNews() {
    var planner = NotificationPlanner()
    let off = NotificationSwitches(finished: false)
    _ = planner.plan(snap([torrent("a")]), switches: off)
    let done = [torrent("a", state: .seeding, progress: 1)]
    #expect(planner.plan(snap(done, at: 1), switches: off).isEmpty)
    #expect(planner.plan(snap(done, at: 2), switches: NotificationSwitches()).isEmpty)
  }
}
