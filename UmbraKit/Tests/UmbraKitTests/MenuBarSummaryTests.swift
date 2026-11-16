import Foundation
import Testing
import UmbraAPI

@testable import UmbraKit

private let now = Date(timeIntervalSince1970: 1_794_493_800)

private func torrent(
  _ hash: String, _ state: Components.Schemas.TorrentState, speed: Int64 = 0,
  name: String? = nil, eta: Int64? = nil, progress: Double = 0.5
) -> Components.Schemas.Torrent {
  var t = row(hash, name ?? "Torrent \(hash)")
  t.state = state
  t.downSpeed = speed
  t.etaSeconds = eta
  t.progress = progress
  return t
}

private func totals(
  _ vpn: Components.Schemas.VpnState = .connected, down: Int64 = 0, up: Int64 = 0,
  slow: Bool = false
) -> Components.Schemas.Transfer {
  var t = transfer(vpn: vpn)
  t.downSpeed = down
  t.upSpeed = up
  t.slowMode = slow
  if vpn == .connected { t.vpnIp = "185.213.4.22" }
  return t
}

private func summary(
  _ torrents: [Components.Schemas.Torrent] = [],
  transfer: Components.Schemas.Transfer? = totals(),
  phase: AppSession.Phase = .running, feed: FeedConnectionState = .live,
  status: Components.Schemas.VpnStatus? = nil, slowMode: Bool = false
) -> MenuBarSummary {
  MenuBarSummary(
    torrents: torrents, transfer: transfer, phase: phase, feed: feed,
    vpn: VpnSummary(
      transfer: transfer, status: status, connection: feed, now: now,
      locale: Locale(identifier: "en_US")),
    slowMode: slowMode)
}

@Suite struct MenuBarCountsLineTests {
  @Test func showsBothCounts() {
    let list =
      (1...5).map { torrent("d\($0)", .downloading) } + (1...6).map { torrent("s\($0)", .seeding) }
    #expect(summary(list).countsLine == "5 downloading · 6 seeding")
  }

  @Test func leavesOutAZeroPart() {
    #expect(summary([torrent("a", .downloading)]).countsLine == "1 downloading")
    #expect(summary([torrent("a", .seeding), torrent("b", .seeding)]).countsLine == "2 seeding")
  }

  @Test func saysNothingActiveWhenBothAreZero() {
    #expect(summary([]).countsLine == "Nothing active")
    // Paused and queued torrents are not active.
    #expect(summary([torrent("a", .paused), torrent("b", .queued)]).countsLine == "Nothing active")
  }

  @Test func countsUseThousandsSeparators() {
    let list = (1...1_204).map { torrent("d\($0)", .downloading) }
    let separator = Locale.current.groupingSeparator ?? ","
    #expect(summary(list).countsLine == "1\(separator)204 downloading")
  }

  @Test func usesTheSessionPhaseWhenNotRunning() {
    let busy = [torrent("a", .downloading)]
    #expect(summary(busy, phase: .starting).countsLine == "Starting…")
    #expect(summary(busy, phase: .reconnecting(attempt: 1)).countsLine == "Reconnecting…")
    #expect(summary(busy, phase: .saving).countsLine == "Saving…")
    #expect(summary(busy, phase: .stopped).countsLine == "Not running")
    #expect(summary(busy, phase: .failed(message: "x", logTail: [])).countsLine == "Not running")
  }

  @Test func saysSoWhenTheLiveListIsNotOpen() {
    let busy = [torrent("a", .downloading)]
    #expect(summary(busy, feed: .connecting).countsLine == "Connecting…")
    #expect(summary(busy, feed: .reconnecting(since: now)).countsLine == "Reconnecting…")
    #expect(summary(busy, feed: .refused).countsLine == "Not connected")
  }
}

@Suite struct MenuBarIconTests {
  @Test func normalWhileTheVpnIsFine() {
    let s = summary([torrent("a", .downloading)])
    #expect(s.icon == .normal)
    #expect(s.icon.symbol == "arrow.up.arrow.down.circle")
  }

  @Test func normalWithNoVpnSetUpOrConnecting() {
    #expect(summary(transfer: totals(.none)).icon == .normal)
    #expect(summary(transfer: totals(.connecting)).icon == .normal)
  }

  @Test func attentionWhenHeld() {
    let s = summary(transfer: totals(.held))
    #expect(s.icon == .attention)
    #expect(s.icon.symbol == "exclamationmark.shield")
  }

  @Test func attentionWhenTheVpnIsDown() {
    #expect(summary(transfer: totals(.down)).icon == .attention)
  }

  @Test func attentionWhenATorrentWaitsForTheVpn() {
    #expect(summary([torrent("a", .waitingForVpn)]).icon == .attention)
  }

  @Test func notConnectedBeatsEverythingElse() {
    let held = totals(.held)
    for phase: AppSession.Phase in [
      .starting, .reconnecting(attempt: 1), .saving, .stopped,
      .failed(message: "x", logTail: []),
    ] {
      #expect(summary(transfer: held, phase: phase).icon == .notConnected)
    }
    #expect(summary(transfer: held, feed: .reconnecting(since: now)).icon == .notConnected)
    #expect(summary(feed: .refused).icon == .notConnected)
    #expect(MenuBarSummary.Icon.notConnected.symbol == "bolt.slash.circle")
  }

  @Test func theThreeIconsDiffer() {
    let symbols = [MenuBarSummary.Icon.normal, .attention, .notConnected].map(\.symbol)
    #expect(Set(symbols).count == 3)
  }
}

@Suite struct MenuBarVpnTests {
  @Test func usesThePopoversWords() {
    let transfer = totals(.connected)
    let vpn = VpnSummary(
      transfer: transfer, status: nil, connection: .live, now: now,
      locale: Locale(identifier: "en_US"))
    let block = summary(transfer: transfer).vpn
    #expect(block?.title == vpn.details.title)
    #expect(block?.sentence == vpn.details.sentence)
    #expect(block?.symbol == vpn.details.symbol)
    #expect(block?.role == .green)
    #expect(block?.address == "185.213.4.22")
    #expect(block?.offersSettings == false)
  }

  @Test func offersVpnSettingsWhenHeldOrDown() {
    for state: Components.Schemas.VpnState in [.held, .down] {
      let block = summary(transfer: totals(state)).vpn
      #expect(block?.offersSettings == true)
      #expect(block?.role == .red)
      #expect(block?.address == nil)
    }
  }

  @Test func neverOffersToStartWithoutAVpnHere() {
    // The block has no such button at all; held only offers the settings.
    let block = summary(transfer: totals(.held)).vpn
    #expect(block?.offersSettings == true)
  }

  @Test func noBlockAndNoSpeedsWhenNotRunning() {
    let s = summary(phase: .stopped)
    #expect(s.vpn == nil)
    #expect(!s.showsSpeeds)
  }
}

@Suite struct MenuBarSpeedTests {
  @Test func showsTheTotals() {
    let s = summary(transfer: totals(down: 8_800_000, up: 1_300_000))
    #expect(s.showsSpeeds)
    #expect(s.downSpeed == "8.4 MB/s")
    #expect(s.upSpeed == "1.2 MB/s")
  }

  @Test func zeroReadsAsZero() {
    let s = summary(transfer: totals())
    #expect(s.downSpeed == "0 B/s")
    #expect(s.upSpeed == "0 B/s")
  }

  @Test func aDashWhileTheLiveListIsNotOpen() {
    let s = summary(transfer: totals(down: 5_000_000), feed: .reconnecting(since: now))
    #expect(s.showsSpeeds)
    #expect(s.downSpeed == Format.dash)
    #expect(s.upSpeed == Format.dash)
  }
}

@Suite struct MenuBarActiveListTests {
  @Test func onlyDownloadsFastestFirst() {
    let list = [
      torrent("slow", .downloading, speed: 100), torrent("seed", .seeding, speed: 9_999),
      torrent("fast", .downloading, speed: 5_000), torrent("idle", .paused, speed: 0),
      torrent("mid", .downloading, speed: 900),
    ]
    #expect(summary(list).active.map(\.id) == ["fast", "mid", "slow"])
  }

  @Test func capsAtFiveAndCountsTheRest() {
    let list = (1...8).map { torrent("t\($0)", .downloading, speed: Int64($0) * 10) }
    let s = summary(list)
    #expect(s.active.map(\.id) == ["t8", "t7", "t6", "t5", "t4"])
    #expect(s.moreActive == 3)
    #expect(s.moreLine == "and 3 more")
  }

  @Test func exactlyFiveHasNoMoreLine() {
    let list = (1...5).map { torrent("t\($0)", .downloading, speed: Int64($0)) }
    let s = summary(list)
    #expect(s.active.count == 5)
    #expect(s.moreActive == 0)
    #expect(s.moreLine == nil)
  }

  @Test func emptyWhenNothingDownloads() {
    let s = summary([torrent("a", .seeding), torrent("b", .paused)])
    #expect(s.active.isEmpty)
    #expect(s.moreLine == nil)
  }

  @Test func tiesKeepAStableOrder() {
    let list = [
      torrent("c", .downloading, name: "Same"), torrent("b", .downloading, name: "Same"),
      torrent("a", .downloading, name: "Other"),
    ]
    #expect(summary(list).active.map(\.id) == ["a", "b", "c"])
    #expect(summary(list.reversed()).active.map(\.id) == ["a", "b", "c"])
  }

  @Test func carriesTheNameTheEtaAndTheProgress() {
    let s = summary([
      torrent("a", .downloading, speed: 1, name: "Big file", eta: 2_460, progress: 0.25),
      torrent("b", .downloading, name: "No eta", eta: nil),
    ])
    #expect(s.active[0].name == "Big file")
    #expect(s.active[0].eta == "41m")
    #expect(s.active[0].progress == 0.25)
    #expect(s.active[1].eta == Format.dash)
  }

}

@Suite struct MenuBarControlsTests {
  private let mixed = [
    torrent("run", .downloading), torrent("seed", .seeding), torrent("p1", .paused),
    torrent("err", .error), torrent("gone", .missingFiles), torrent("q", .queued),
  ]

  @Test func pauseAllSendsEverythingNotPaused() {
    let s = summary(mixed)
    #expect(s.canPauseAll)
    #expect(s.pauseAllHashes == ["run", "seed", "err", "gone", "q"])
  }

  @Test func resumeAllSendsPausedAndStopped() {
    let s = summary(mixed)
    #expect(s.canResumeAll)
    #expect(s.resumeAllHashes == ["p1", "err", "gone"])
  }

  @Test func pauseAllIsOffWhenEverythingIsPaused() {
    let s = summary([torrent("a", .paused), torrent("b", .paused)])
    #expect(!s.canPauseAll)
    #expect(s.pauseAllHashes.isEmpty)
    #expect(s.canResumeAll)
  }

  @Test func resumeAllIsOffWhenNothingIsStopped() {
    let s = summary([torrent("a", .downloading), torrent("b", .seeding)])
    #expect(s.canPauseAll)
    #expect(!s.canResumeAll)
    #expect(s.resumeAllHashes.isEmpty)
  }

  @Test func bothAreOffWithNoTorrents() {
    let s = summary([])
    #expect(!s.canPauseAll)
    #expect(!s.canResumeAll)
  }

  @Test func everythingIsOffWhenNotConnected() {
    for s in [
      summary(mixed, phase: .starting), summary(mixed, feed: .reconnecting(since: now)),
      summary(mixed, phase: .stopped),
    ] {
      #expect(!s.canPauseAll)
      #expect(!s.canResumeAll)
      #expect(s.pauseAllHashes.isEmpty)
      #expect(s.resumeAllHashes.isEmpty)
      #expect(!s.slowModeEnabled)
    }
  }

  @Test func slowModeShowsTheStateGivenAndIsOnlyUsableWhenConnected() {
    #expect(summary(slowMode: true).slowMode)
    #expect(!summary(slowMode: false).slowMode)
    #expect(summary().slowModeEnabled)
  }
}

@MainActor @Suite struct MenuBarModelTests {
  private func model(lifetime: Duration = .seconds(10)) -> MenuBarModel {
    let store = TorrentStore()
    return MenuBarModel(
      session: AppSession(fixture: store, phase: .stopped),
      window: MainWindowModel(store: store, defaults: throwawayDefaults()),
      failureLifetime: lifetime)
  }

  @Test func aRefusalBecomesOneLine() {
    let model = model()
    model.show(
      ActionFailure(action: .pause, count: 12, message: "Umbra is busy. Try again in a moment."))
    #expect(
      model.failureLine == "Couldn't pause 12 torrents. Umbra is busy. Try again in a moment.")
    model.show(nil)
    #expect(model.failureLine == nil)
  }

  @Test func theLineGoesAwayByItself() async {
    let model = model(lifetime: .milliseconds(20))
    model.show(ActionFailure(action: .resume, count: 1, message: "No."))
    #expect(model.failureLine != nil)
    #expect(await eventually { model.failureLine == nil })
  }

  @Test func doesNothingWhileNotConnected() async {
    let model = model()
    #expect(await model.pauseAll() == nil)
    #expect(await model.resumeAll() == nil)
    #expect(await model.setSlowMode(true) == nil)
  }
}
