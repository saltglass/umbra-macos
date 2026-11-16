import Foundation
import Testing
import UmbraAPI

@testable import UmbraKit

// What the app does around a sleep of the Mac (WakeRecovery), and what the
// VPN line says meanwhile. Times are made up: `at(5)` is 5 seconds after a
// fixed start, so nothing here waits.

private let start = ContinuousClock.now
private func at(_ seconds: Double) -> ContinuousClock.Instant { start + .seconds(seconds) }

/// A recovery that has been through a sleep and a wake, and the steps the
/// wake asked for.
private func woken(asleepFor hours: Double = 6) -> (WakeRecovery, [WakeRecovery.Step]) {
  var wake = WakeRecovery()
  wake.willSleep(at: at(0), connected: true)
  let steps = wake.didWake(at: at(hours * 3600), connected: true)
  return (wake, steps)
}

@Suite struct WakeRecoveryTests {
  @Test func wakingReopensTheFeedAndAsksAboutTheVpnAtOnce() {
    let (wake, steps) = woken()
    #expect(steps == [.reopenFeed, .checkVpn(round: 1)])
    #expect(wake.isChecking)
  }

  @Test func goingToSleepAlreadyShowsChecking() {
    // So the first thing on screen after waking is right, even before the
    // wake notice arrives.
    var wake = WakeRecovery()
    wake.willSleep(at: at(0), connected: true)
    #expect(wake.isChecking)
    #expect(wake.isAsleep)
  }

  @Test func aConnectedAnswerEndsTheCheckOnceTheFeedIsOpen() {
    var (wake, _) = woken()
    let t = 6 * 3600.0
    wake.answered(.connected, round: 1, feedLive: false, at: at(t + 0.1))
    #expect(wake.isChecking, "the feed isn't open again yet, so its old state would show")
    #expect(wake.tick(at: at(t + 0.5), connected: true, feedLive: true) == [])
    #expect(!wake.isChecking)
  }

  @Test func heldAndNoVpnAreSettledToo() {
    for state: Components.Schemas.VpnState in [.held, .none] {
      var (wake, _) = woken()
      wake.answered(state, round: 1, feedLive: true, at: at(6 * 3600 + 0.1))
      #expect(!wake.isChecking, "\(state)")
    }
  }

  @Test func downOrConnectingIsAskedAgainAFewSecondsLater() {
    for state: Components.Schemas.VpnState? in [.down, .connecting, nil] {
      var (wake, _) = woken()
      let t = 6 * 3600.0
      wake.answered(state, round: 1, feedLive: true, at: at(t + 0.1))
      #expect(wake.isChecking)
      #expect(wake.tick(at: at(t + 2), connected: true, feedLive: true) == [], "too soon")
      #expect(wake.tick(at: at(t + 4), connected: true, feedLive: true) == [.checkVpn(round: 1)])
      // Still out: no second check on top of it.
      #expect(wake.tick(at: at(t + 9), connected: true, feedLive: true) == [])
      wake.answered(.connected, round: 1, feedLive: true, at: at(t + 9.5))
      #expect(!wake.isChecking)
    }
  }

  @Test func itGivesUpAfterTwentySecondsAndShowsWhatUmbraSays() {
    var (wake, _) = woken()
    let t = 6 * 3600.0
    wake.answered(.down, round: 1, feedLive: true, at: at(t + 0.1))
    _ = wake.tick(at: at(t + 4), connected: true, feedLive: true)
    wake.answered(.down, round: 1, feedLive: true, at: at(t + 4.1))
    #expect(wake.tick(at: at(t + 20), connected: true, feedLive: true) == [])
    #expect(!wake.isChecking)
  }

  @Test func repeatedWakesDoNotStackWork() {
    var (wake, _) = woken()
    let t = 6 * 3600.0
    // macOS can say "woke" more than once (a dark wake, then the screen).
    #expect(wake.didWake(at: at(t + 1), connected: true) == [])
    #expect(wake.didWake(at: at(t + 2), connected: true) == [])
    #expect(wake.isChecking)
    // Once the first check is back, a later wake asks again, but the feed
    // isn't reopened a second time.
    wake.answered(.down, round: 1, feedLive: true, at: at(t + 3))
    #expect(wake.didWake(at: at(t + 3.5), connected: true) == [.checkVpn(round: 1)])
  }

  @Test func nothingHappensWhenNotConnectedToUmbra() {
    var wake = WakeRecovery()
    wake.willSleep(at: at(0), connected: false)
    #expect(!wake.isChecking)
    #expect(wake.didWake(at: at(3600), connected: false) == [])
    #expect(!wake.isChecking)
    #expect(wake.tick(at: at(3601), connected: false, feedLive: false) == [])
  }

  @Test func losingUmbraWhileCheckingStopsTheCheck() {
    // The helper restarting shows its own "Reconnecting…".
    var (wake, _) = woken()
    #expect(wake.tick(at: at(6 * 3600 + 1), connected: false, feedLive: false) == [])
    #expect(!wake.isChecking)
  }

  @Test func anAnswerFromBeforeTheNextSleepIsIgnored() {
    var (wake, _) = woken()
    let t = 6 * 3600.0
    // A check is out when the Mac sleeps again; its answer comes after.
    wake.willSleep(at: at(t + 1), connected: true)
    let steps = wake.didWake(at: at(t + 7200), connected: true)
    #expect(steps == [.reopenFeed, .checkVpn(round: 2)])
    wake.answered(.connected, round: 1, feedLive: true, at: at(t + 7200.1))
    #expect(wake.isChecking, "a pre-sleep answer must not end the check")
    wake.answered(.connected, round: 2, feedLive: true, at: at(t + 7200.2))
    #expect(!wake.isChecking)
  }

  @Test func aWakeNoticeThatNeverCameIsMadeUpFor() {
    // Swift's clock keeps going during sleep, so the first tick after a
    // long sleep sees it at once.
    var wake = WakeRecovery()
    wake.willSleep(at: at(0), connected: true)
    #expect(wake.tick(at: at(5), connected: true, feedLive: true) == [], "not a sleep yet")
    #expect(
      wake.tick(at: at(3600), connected: true, feedLive: true) == [
        .reopenFeed, .checkVpn(round: 1),
      ])
    #expect(!wake.isAsleep)
  }
}

@Suite struct AfterWakeWordsTests {
  private func totals(_ vpn: Components.Schemas.VpnState) -> Components.Schemas.Transfer {
    var t = Components.Schemas.Transfer(
      downSpeed: 0, upSpeed: 0, downLimit: 0, upLimit: 0, slowMode: false, sessionDownloaded: 0,
      sessionUploaded: 0, freeSpace: 100 << 30, lowSpace: 5 << 30, incoming: false, dhtNodes: 0,
      vpn: vpn)
    t.vpnIp = "185.213.4.22"
    return t
  }

  @Test func aConnectedFromBeforeTheSleepReadsAsChecking() {
    let summary = VpnSummary(
      transfer: totals(.connected), status: nil, connection: .live, waking: true)
    #expect(summary.pill.kind == .unknown)
    #expect(summary.pill.title == "Checking VPN…")
    #expect(summary.pill.address == nil, "no address from before the sleep")
    #expect(summary.pill.help.contains("just woke up"))
    #expect(summary.details.title == "Checking…")
    #expect(summary.details.sentence.contains("Nothing goes outside the VPN"))
    #expect(!summary.details.offersCheckAgain)
  }

  @Test func downAndConnectingAndUnknownReadAsCheckingToo() {
    for state: Components.Schemas.VpnState in [.down, .connecting] {
      let summary = VpnSummary(
        transfer: totals(state), status: nil, connection: .live, waking: true)
      #expect(summary.pill.title == "Checking VPN…", "\(state)")
    }
    let reopening = VpnSummary(
      transfer: totals(.connected), status: nil, connection: .connecting, waking: true)
    #expect(reopening.pill.title == "Checking VPN…")
  }

  @Test func heldAndNoVpnAreShownAsTheyAre() {
    for state: Components.Schemas.VpnState in [.held, .none] {
      let waking = VpnSummary(transfer: totals(state), status: nil, connection: .live, waking: true)
      let awake = VpnSummary(transfer: totals(state), status: nil, connection: .live)
      #expect(waking == awake, "\(state)")
    }
  }

  @Test func withoutWakingNothingChanges() {
    let summary = VpnSummary(transfer: totals(.connected), status: nil, connection: .live)
    #expect(summary.pill.kind == .connected)
    #expect(summary.pill.address == "185.213.4.22")
  }

  @Test func theDownBannerWaitsWhileWaking() {
    #expect(StatusBanner.list(transfer: totals(.down)).map(\.kind) == [.vpnDown])
    #expect(StatusBanner.list(transfer: totals(.down), waking: true).isEmpty)
    // Held isn't changed by a sleep: its banner stays.
    #expect(StatusBanner.list(transfer: totals(.held), waking: true).map(\.kind) == [.vpnHeld])
  }
}
