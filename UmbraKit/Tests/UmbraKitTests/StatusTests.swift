import Foundation
import Testing
import UmbraAPI

@testable import UmbraKit

private let english = Locale(identifier: "en_US")
private let now = Date(timeIntervalSince1970: 1_794_493_800)

private func totals(
  _ vpn: Components.Schemas.VpnState, ip: String? = nil, free: Int64 = 100 << 30,
  low: Int64 = 5 << 30, problem: Components.Schemas.EngineProblem? = nil
) -> Components.Schemas.Transfer {
  var t = Components.Schemas.Transfer(
    downSpeed: 0, upSpeed: 0, downLimit: 0, upLimit: 0, slowMode: false, sessionDownloaded: 0,
    sessionUploaded: 0, freeSpace: free, lowSpace: low, incoming: false, dhtNodes: 0, vpn: vpn)
  t.vpnIp = ip
  t.engineProblem = problem
  return t
}

private func vpnStatus(
  _ state: Components.Schemas.VpnState
) -> Components.Schemas.VpnStatus {
  Components.Schemas.VpnStatus(
    state: state, configured: state != .none, saved: [],
    failover: .init(enabled: false, minutes: 5))
}

private func summary(
  _ transfer: Components.Schemas.Transfer?, _ status: Components.Schemas.VpnStatus? = nil,
  connection: FeedConnectionState = .live
) -> VpnSummary {
  VpnSummary(
    transfer: transfer, status: status, connection: connection, now: now, locale: english)
}

@Suite struct VpnPillTests {
  @Test func connectedShowsTheAddressInGreen() {
    let pill = summary(totals(.connected, ip: "185.213.4.22")).pill
    #expect(pill.kind == .connected)
    #expect(pill.title == "VPN")
    #expect(pill.address == "185.213.4.22")
    #expect(pill.role == .green)
    #expect(pill.help.contains("185.213.4.22"))
  }

  @Test func eachOtherStateHasItsWordsAndColour() {
    let cases: [(Components.Schemas.VpnState, String, ColorRole)] = [
      (.connecting, "VPN connecting…", .orange), (.down, "VPN down", .red),
      (.held, "VPN held", .red), (.none, "No VPN", .secondary),
    ]
    for (state, title, role) in cases {
      let pill = summary(totals(state)).pill
      #expect(pill.title == title)
      #expect(pill.role == role)
      #expect(pill.address == nil)
    }
  }

  @Test func anAddressIsNeverShownUnlessConnected() {
    // Even if a stale address came along with a down state.
    var status = vpnStatus(.down)
    status.vpnIp = "185.213.4.22"
    #expect(summary(totals(.down, ip: "185.213.4.22"), status).pill.address == nil)
    #expect(!summary(totals(.down, ip: "1.2.3.4"), status).pill.help.contains("1.2.3.4"))
  }

  @Test func connectedWithoutAnAddressYetFallsBackToTheVpnAnswer() {
    var status = vpnStatus(.connected)
    status.vpnIp = "185.213.4.22"
    #expect(summary(totals(.connected), status).pill.address == "185.213.4.22")
    #expect(summary(totals(.connected), nil).pill.address == nil)
  }

  @Test func theFeedWinsWhenItDisagreesWithGetVpn() {
    // GET /vpn (up to 30 s old) says connected; the feed says it just dropped.
    var status = vpnStatus(.connected)
    status.vpnIp = "185.213.4.22"
    status.forwardedPort = 51413
    status.since = now.addingTimeInterval(-3600)
    let result = summary(totals(.down), status)
    #expect(result.pill.kind == .down)
    // The old answer's details are not shown next to the new state.
    #expect(result.details.facts.isEmpty)
    #expect(result.pill.address == nil)
    #expect(!result.details.sentence.contains("through the VPN"))
  }

  @Test func theOldMessageIsNotUsedForADifferentState() {
    var status = vpnStatus(.down)
    status.message = "The tunnel stopped answering."
    #expect(summary(totals(.connecting), status).details.sentence.hasPrefix("The tunnel is coming"))
    #expect(summary(totals(.down), status).details.sentence == "The tunnel stopped answering.")
  }

  @Test func withoutTheFeedsTotalsGetVpnIsUsed() {
    #expect(summary(nil, vpnStatus(.down)).pill.kind == .down)
  }

  @Test func aFeedThatIsNotOpenMeansTheStateIsUnknown() {
    var status = vpnStatus(.connected)
    status.vpnIp = "185.213.4.22"
    for connection: FeedConnectionState in [
      .connecting, .reconnecting(since: now), .refused,
    ] {
      let pill = summary(totals(.connected, ip: "185.213.4.22"), status, connection: connection)
        .pill
      #expect(pill.kind == .unknown)
      #expect(pill.title == "VPN unknown")
      #expect(pill.address == nil)
      #expect(pill.role == .secondary)
    }
  }

  @Test func beforeAnythingIsHeardItSaysChecking() {
    let result = summary(nil, nil, connection: .connecting)
    #expect(result.pill.title == "Checking VPN…")
    #expect(!result.details.offersCheckAgain)
  }
}

@Suite struct VpnPopoverTests {
  @Test func connectedListsAddressPortAndWhenItChanged() {
    var status = vpnStatus(.connected)
    status.saved = [.init(id: "a", name: "AirVPN Zurich", inUse: true)]
    status.forwardedPort = 51413
    status.since = now.addingTimeInterval(-47 * 60)
    let details = summary(totals(.connected, ip: "185.213.4.22"), status).details
    #expect(details.title == "Connected via AirVPN Zurich")
    #expect(
      details.facts.map { "\($0.label): \($0.value)" } == [
        "Address peers see: 185.213.4.22", "Forwarded port: 51413",
        "Last changed: 47 minutes ago",
      ])
    #expect(details.offersCheckAgain)
  }

  @Test func connectedWithNoAddressYet() {
    #expect(summary(totals(.connected), nil).details.facts.first?.value == "Checking…")
    var status = vpnStatus(.connected)
    status.ipError = "timed out"
    #expect(summary(totals(.connected), status).details.facts.first?.value == "Couldn't check")
  }

  @Test func recentChangeSaysJustNow() {
    var status = vpnStatus(.down)
    status.since = now.addingTimeInterval(-10)
    #expect(summary(totals(.down), status).details.facts.last?.value == "Just now")
  }

  @Test func downAndConnectingOfferCheckAgainButHeldAndNoneDoNot() {
    #expect(summary(totals(.down)).details.offersCheckAgain)
    #expect(summary(totals(.connecting)).details.offersCheckAgain)
    #expect(!summary(totals(.held)).details.offersCheckAgain)
    #expect(!summary(totals(.none)).details.offersCheckAgain)
  }

  @Test func downUsesUmbrasOwnWordsOtherwiseTheKillSwitchSentence() {
    #expect(
      summary(totals(.down)).details.sentence
        == "The kill switch has stopped every torrent until the VPN reconnects.")
    var status = vpnStatus(.down)
    status.message = "No answer from the server."
    #expect(summary(totals(.down), status).details.sentence == "No answer from the server.")
  }

  @Test func noVpnSaysSoAndThatItIsSetUpInSettings() {
    var status = vpnStatus(.none)
    status.realIp = "203.0.113.9"
    let details = summary(totals(.none), status).details
    #expect(details.title == "No VPN")
    #expect(details.sentence.contains("No VPN is set up"))
    #expect(details.sentence.contains("Settings"))
    #expect(details.facts.map(\.value) == ["203.0.113.9"])
  }

  @Test func nothingIsCalledProtectedUnlessConnected() {
    for state: Components.Schemas.VpnState in [.connecting, .down, .held, .none] {
      let details = summary(totals(state)).details
      let words = (details.title + details.sentence).lowercased()
      #expect(!words.contains("protected"))
      #expect(!words.contains("through the vpn"))
    }
  }
}

@Suite struct BannerTests {
  @Test func nothingWrongNoBanners() {
    #expect(StatusBanner.list(transfer: totals(.connected, ip: "1.2.3.4")).isEmpty)
    #expect(StatusBanner.list(transfer: totals(.none)).isEmpty)
    #expect(StatusBanner.list(transfer: nil).isEmpty)
  }

  @Test func connectingHasNoBannerAsOnTheWebPage() {
    #expect(StatusBanner.list(transfer: totals(.connecting)).isEmpty)
  }

  @Test func vpnDown() throws {
    let banner = try #require(StatusBanner.list(transfer: totals(.down)).first)
    #expect(banner.kind == .vpnDown)
    #expect(banner.message == "VPN is down: all torrents are stopped until it reconnects.")
    #expect(banner.role == .red)
    #expect(banner.actions == [.checkAgain, .openVpnSettings])
    #expect(banner.actions.map(\.title) == ["Check Again", "Open VPN Settings…"])
  }

  @Test func vpnHeld() throws {
    let banner = try #require(StatusBanner.list(transfer: totals(.held)).first)
    #expect(banner.kind == .vpnHeld)
    #expect(banner.message.hasPrefix("The VPN was removed: all torrents are stopped"))
    #expect(banner.role == .red)
  }

  @Test func engineProblemUsesUmbrasWordsAndOffersNothing() throws {
    let problem = Components.Schemas.EngineProblem(
      message: "the engine can't listen on TCP port 6881", portBusy: true)
    let banner = try #require(
      StatusBanner.list(transfer: totals(.connected, problem: problem)).first)
    #expect(banner.kind == .engineProblem)
    #expect(
      banner.message == "Every torrent is stopped: the engine can't listen on TCP port 6881")
    #expect(banner.role == .red)
    #expect(banner.actions.isEmpty)
  }

  @Test func diskBannerRule() throws {
    let low = try #require(StatusBanner.list(transfer: totals(.none, free: 4 << 30)).first)
    #expect(low.kind == .lowSpace)
    #expect(low.message == "Disk almost full: 4.0 GB free.")
    #expect(low.role == .orange)
    // At the level exactly: not below it.
    #expect(StatusBanner.list(transfer: totals(.none, free: 5 << 30)).isEmpty)
    // Level 0 means never warn; negative free space means unknown.
    #expect(StatusBanner.list(transfer: totals(.none, free: 0, low: 0)).isEmpty)
    #expect(StatusBanner.list(transfer: totals(.none, free: -1)).isEmpty)
  }

  @Test func severalStackMostImportantFirst() {
    let problem = Components.Schemas.EngineProblem(message: "x", portBusy: false)
    let all = StatusBanner.list(
      transfer: totals(.down, free: 1 << 30, problem: problem))
    #expect(all.map(\.kind) == [.engineProblem, .vpnDown, .lowSpace])
    #expect(
      StatusBanner.list(transfer: totals(.held, free: 1 << 30)).map(\.kind) == [
        .vpnHeld, .lowSpace,
      ])
  }

  @Test func noBannerCanBeDismissed() {
    let problem = Components.Schemas.EngineProblem(message: "x", portBusy: false)
    let all = StatusBanner.list(transfer: totals(.down, free: 1 << 30, problem: problem))
    #expect(all.allSatisfy { !$0.isDismissible })
  }

  @Test func aBannerGoesWhenUmbraSaysTheTroubleIsOver() {
    #expect(!StatusBanner.list(transfer: totals(.down)).isEmpty)
    #expect(StatusBanner.list(transfer: totals(.connected, ip: "1.2.3.4")).isEmpty)
  }
}

@Suite struct SessionScreenTests {
  @Test func theListStaysWhileReconnectingIfThereIsOne() {
    #expect(SessionScreen.showsList(phase: .running, loaded: true))
    #expect(SessionScreen.showsList(phase: .reconnecting(attempt: 1), loaded: true))
    #expect(!SessionScreen.showsList(phase: .reconnecting(attempt: 1), loaded: false))
  }

  @Test func otherPhasesReplaceTheList() {
    let others: [AppSession.Phase] = [
      .starting, .saving, .stopped, .failed(message: "x", logTail: []),
    ]
    for phase in others {
      #expect(!SessionScreen.showsList(phase: phase, loaded: true))
    }
  }

  @Test func theQuietNote() {
    #expect(SessionScreen.note(phase: .running, connection: .live) == nil)
    #expect(SessionScreen.note(phase: .running, connection: .connecting) == nil)
    #expect(
      SessionScreen.note(phase: .running, connection: .reconnecting(since: now))
        == "Reconnecting…")
    #expect(
      SessionScreen.note(phase: .reconnecting(attempt: 2), connection: .connecting)
        == "Reconnecting…")
    #expect(
      SessionScreen.note(phase: .running, connection: .refused)
        == "Umbra turned the connection away")
  }
}

@Suite struct VpnCheckTests {
  let connection = Connection(
    baseURL: URL(string: "http://127.0.0.1:7980")!, credential: .apiKey("key"))
  let answer = """
    {"state":"connected","configured":true,"saved":[],"failover":{"enabled":false,"minutes":5},\
    "vpnIp":"185.213.4.22"}
    """

  @Test func checkAgainAsksGetVpnWithRefreshAndReturnsTheAnswer() async throws {
    let transport = RecordingTransport(["getVpn": .json(answer)])
    let actions = TorrentActions(connection: connection, transport: transport)
    let status = try await actions.checkVpnAgain()
    #expect(status.state == .connected)
    #expect(status.vpnIp == "185.213.4.22")
    let sent = try #require(await transport.sent.first)
    #expect(sent.operation == "getVpn")
    #expect(sent.method == .get)
    #expect(sent.path == "/vpn?refresh=true")
  }

  @Test func aRefusalComesBackInUmbrasWords() async throws {
    let transport = RecordingTransport([
      "getVpn": .error(.unauthorized, code: "unauthorized", message: "Sign in again.")
    ])
    let actions = TorrentActions(connection: connection, transport: transport)
    do {
      _ = try await actions.checkVpnAgain()
      Issue.record("didn't throw")
    } catch {
      #expect(error.message == "Sign in again.")
    }
  }

  @MainActor @Test func theSessionDoesNothingWhileNotConnected() async throws {
    let session = AppSession(fixture: TorrentStore())
    try await session.checkVpnAgain()
    #expect(session.vpnStatus == nil)
  }
}
