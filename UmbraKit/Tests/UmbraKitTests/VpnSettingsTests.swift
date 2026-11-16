import Foundation
import HTTPTypes
import Testing
import UmbraAPI

@testable import UmbraKit

private let connection = Connection(
  baseURL: URL(string: "http://127.0.0.1:7980")!, credential: .apiKey("key"))

/// Two saved VPNs (made-up names and documentation addresses), the first in use.
private let twoSavedJSON = """
  {"state":"connected","configured":true,"vpnIp":"198.51.100.7","forwardedPort":51413,\
  "since":"2026-11-13T09:00:00Z",\
  "saved":[{"id":"a","name":"Example VPN One","inUse":true,"endpoint":"203.0.113.10:51820"},\
  {"id":"b","name":"Example VPN Two","inUse":false}],\
  "failover":{"enabled":false,"minutes":5}}
  """
private let refusedJSON = """
  {"code":"invalid","message":"Some fields need attention.",\
  "fields":{"config":"This isn't a WireGuard configuration: it has no [Interface] section."}}
  """
private let refusal = RecordingTransport.Reply.json(refusedJSON, status: .unprocessableContent)

/// A configuration that looks like one but holds a made-up key, never a real one.
private let fakeKey = "TEST-ONLY-NOT-A-KEY-0000000000000000000000000="
private let fakeConfig = "[Interface]\nPrivateKey = \(fakeKey)\n"

private func actions(
  _ replies: [String: RecordingTransport.Reply]
) -> (SettingsActions, RecordingTransport) {
  let transport = RecordingTransport(replies)
  return (SettingsActions(connection: connection, transport: transport), transport)
}

// MARK: The calls

/// Each VPN operation is the right request, and a refusal carries Umbra's words.
@Suite struct VpnActionsTests {
  @Test func readsTheState() async throws {
    let (actions, transport) = actions(["getVpn": .json(twoSavedJSON)])
    let status = try await actions.vpn(refresh: true)
    #expect(status.saved.map(\.name) == ["Example VPN One", "Example VPN Two"])
    let sent = try #require(await transport.sent.first)
    #expect(sent.method == .get && sent.path == "/vpn?refresh=true")
    _ = try await actions.vpn()
    #expect(await transport.sent.last?.path == "/vpn")
  }

  @Test func addSendsTheConfigurationAndName() async throws {
    let (actions, transport) = actions([
      "addVpn": .json(#"{"id":"c","name":"Example VPN Three","inUse":false}"#, status: .created)
    ])
    let saved = try await actions.addVpn(VpnConfiguration(fakeConfig), name: "Example VPN Three")
    #expect(saved.id == "c")
    let sent = try #require(await transport.sent.last)
    #expect(sent.method == .post && sent.path == "/vpn/configs")
    #expect(sent.json == ["config": fakeConfig, "name": "Example VPN Three"])
  }

  @Test func editSendsOnlyWhatChanged() async throws {
    let (actions, transport) = actions([:])
    try await actions.editVpn(id: "a", name: "Renamed", forwardedPort: 0)
    try await actions.editVpn(id: "a", configuration: VpnConfiguration(fakeConfig))
    let sent = await transport.sent
    #expect(sent[0].method == .patch && sent[0].path == "/vpn/configs/a")
    #expect(sent[0].json == ["name": "Renamed", "forwardedPort": 0])
    #expect(sent[1].json == ["config": fakeConfig])
  }

  @Test func removeUseOrderFailoverAndStartWithout() async throws {
    let (actions, transport) = actions([:])
    try await actions.removeVpn(id: "a")
    try await actions.useVpn(id: "b")
    try await actions.orderVpns(["b", "a"])
    try await actions.setVpnFailover(enabled: true, minutes: 10)
    try await actions.startWithoutVpn()
    let sent = await transport.sent
    #expect(sent.map(\.method) == [.delete, .post, .put, .put, .post])
    #expect(
      sent.map(\.path) == [
        "/vpn/configs/a", "/vpn/configs/b/use", "/vpn/order", "/vpn/failover",
        "/vpn/start-without",
      ])
    #expect(sent[2].json == ["ids": ["b", "a"]])
    #expect(sent[3].json == ["enabled": true, "minutes": 10])
  }

  @Test func everyCallPassesOnARefusal() async {
    let notFound = RecordingTransport.Reply.error(
      .notFound, code: "not_found", message: "No saved VPN has that id.")
    let (actions, _) = actions([
      "getVpn": .error(.unauthorized, code: "unauthorized", message: "Sign in first."),
      "addVpn": refusal, "editVpn": refusal, "removeVpn": notFound, "useVpn": notFound,
      "orderVpns": refusal, "putVpnFailover": refusal,
      "startWithoutVpn": .error(.unauthorized, code: "unauthorized", message: "Sign in first."),
    ])
    let calls: [(String, @Sendable () async throws -> Void)] = [
      ("Sign in first.", { _ = try await actions.vpn() }),
      ("Some fields need attention.", { _ = try await actions.addVpn(VpnConfiguration("x")) }),
      ("Some fields need attention.", { try await actions.editVpn(id: "a", name: "n") }),
      ("No saved VPN has that id.", { try await actions.removeVpn(id: "a") }),
      ("No saved VPN has that id.", { try await actions.useVpn(id: "a") }),
      ("Some fields need attention.", { try await actions.orderVpns(["a"]) }),
      (
        "Some fields need attention.",
        { try await actions.setVpnFailover(enabled: true, minutes: 0) }
      ),
      ("Sign in first.", { try await actions.startWithoutVpn() }),
    ]
    for (message, call) in calls {
      let error = await #expect(throws: UmbraError.self) { try await call() }
      #expect(error?.message == message)
    }
  }
}

// MARK: The model

@MainActor
private func model(
  _ replies: [String: RecordingTransport.Reply]
) async -> (VpnSettingsModel, RecordingTransport, FakeVpnSource) {
  let (actions, transport) = actions(replies)
  let source = FakeVpnSource()
  source.settingsActions = actions
  let model = VpnSettingsModel(source: source)
  _ = await eventually { model.phase == .loaded }
  return (model, transport, source)
}

@MainActor @Suite struct VpnSettingsModelTests {
  @Test func loadsAndSaysWhoIsNext() async {
    let (model, _, _) = await model(["getVpn": .json(twoSavedJSON)])
    #expect(model.saved.map(\.id) == ["a", "b"])
    #expect(model.nextInLine?.id == "b")
    #expect(model.noVpnSituation == nil)
  }

  @Test func aRefusedReorderGoesBackAndSaysWhy() async {
    let (model, transport, _) = await model([
      "getVpn": .json(twoSavedJSON), "orderVpns": refusal,
    ])
    model.move("b", by: -1)
    // Shown at once...
    #expect(model.saved.map(\.id) == ["b", "a"])
    #expect(await eventually { model.refusal != nil && !model.isSending })
    // ...and put back once Umbra says no.
    #expect(model.saved.map(\.id) == ["a", "b"])
    #expect(model.refusal?.message == "Some fields need attention.")
    #expect(await transport.sent.contains { $0.operation == "orderVpns" })
  }

  @Test func dragMovesWorkLikeTheList() async {
    let (model, transport, _) = await model(["getVpn": .json(twoSavedJSON)])
    model.move(fromOffsets: [0], toOffset: 2)
    #expect(await eventually { !model.isSending })
    let order = await transport.sent.first { $0.operation == "orderVpns" }
    #expect(order?.json == ["ids": ["b", "a"]])
    #expect(!model.canMove("a", by: -1) && model.canMove("a", by: 1))
  }

  @Test func theForwardedPortOfTheVpnInUseIsSetFromThePage() async {
    let (model, transport, _) = await model(["getVpn": .json(twoSavedJSON)])
    guard let inUse = model.saved.first(where: \.inUse) else {
      Issue.record("the made-up answer has no VPN in use")
      return
    }
    // The same port again sends nothing.
    model.setForwardedPort(inUse.forwardedPort ?? 0)
    model.setForwardedPort(40_000)
    #expect(await eventually { !model.isSending })
    let edits = await transport.sent.filter { $0.operation == "editVpn" }
    #expect(edits.count == 1)
    #expect(edits.first?.json == ["forwardedPort": 40000])
  }

  @Test func oneRequestAtATimeInOrder() async {
    let (model, transport, _) = await model(["getVpn": .json(twoSavedJSON)])
    model.use("b")
    model.setFailover(enabled: true)
    model.setFailover(minutes: 12)
    #expect(await eventually { !model.isSending })
    let writes = await transport.sent.map(\.operation).filter { $0 != "getVpn" }
    #expect(writes == ["useVpn", "putVpnFailover", "putVpnFailover"])
    let last = await transport.sent.last { $0.operation == "putVpnFailover" }
    #expect(last?.json == ["enabled": true, "minutes": 12])
  }

  @Test func readsAgainWhenTheVpnSettingsChangeOrTheFeedStateDoes() async {
    let (model, transport, source) = await model(["getVpn": .json(twoSavedJSON)])
    let before = await transport.sent.count
    source.store.announceSettingsChanged("vpn")
    #expect(await eventually { await transport.sent.count == before + 1 })
    // Another group: nothing.
    source.store.announceSettingsChanged("speed")
    // The feed's VPN state changes: read again.
    source.liveTransfer = transfer(.connected)
    source.liveTransfer = transfer(.down)
    #expect(await eventually { await transport.sent.count >= before + 2 })
    _ = model
  }

  @Test func aSheetsRefusalComesBackToTheSheetNotThePage() async {
    let (model, _, _) = await model(["getVpn": .json(twoSavedJSON), "addVpn": refusal])
    var draft = VpnPasteDraft()
    draft.text = fakeConfig
    let error = await model.add(draft)
    #expect(
      error.map(VpnSettingsModel.explanation)
        == "This isn't a WireGuard configuration: it has no [Interface] section.")
    #expect(model.refusal == nil)
  }

  @Test func removeAsksInTheWebPagesWords() {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let status = try! decoder.decode(
      Components.Schemas.VpnStatus.self, from: Data(twoSavedJSON.utf8))
    let model = VpnSettingsModel(fixture: status)
    #expect(
      model.removeQuestion(for: "a")?.message
        == "It's in use: torrents switch to “Example VPN Two”.")
    #expect(model.removeQuestion(for: "b")?.message == "It isn't in use, so nothing stops.")
    var one = status
    one.saved.removeLast()
    let last = VpnSettingsModel(fixture: one).removeQuestion(for: "a")
    #expect(last?.title == "Remove the VPN?")
    #expect(last?.button == "Remove VPN")
    #expect(last?.message.contains("stays held") == true)
  }

  /// The configuration is a secret: after it is sent, nothing the model
  /// holds or prints contains it, and the draft never shows it either.
  @Test func aSentConfigurationLeavesNoTrace() async {
    let (model, transport, _) = await model([
      "getVpn": .json(twoSavedJSON),
      "addVpn": .json(#"{"id":"c","name":"Example VPN Three","inUse":false}"#, status: .created),
    ])
    var draft = VpnPasteDraft(name: "Example VPN Three")
    draft.text = fakeConfig
    for text in [String(describing: draft), String(reflecting: draft), "\(draft)", dumpText(draft)]
    {
      #expect(!text.contains(fakeKey))
    }
    #expect(await model.add(draft) == nil)
    draft.clear()
    #expect(draft.text.isEmpty)
    // It did go to Umbra...
    #expect(await transport.sent.contains { $0.body.contains(fakeKey) })
    // ...and is nowhere in the model.
    for text in [dumpText(model), String(describing: model), dumpText(model.status)] {
      #expect(!text.contains(fakeKey))
    }
    let configuration = VpnConfiguration(fakeConfig)
    for text in [
      String(describing: configuration), String(reflecting: configuration), dumpText(configuration),
    ] {
      #expect(!text.contains(fakeKey))
    }
  }
}

private func dumpText<T>(_ value: T) -> String {
  var text = ""
  dump(value, to: &text)
  return text
}

private func transfer(
  _ vpn: Components.Schemas.VpnState, reason: Components.Schemas.VpnHeldReason? = nil
) -> Components.Schemas.Transfer {
  var t = Components.Schemas.Transfer(
    downSpeed: 0, upSpeed: 0, downLimit: 0, upLimit: 0, slowMode: false, sessionDownloaded: 0,
    sessionUploaded: 0, freeSpace: 100 << 30, lowSpace: 0, incoming: false, dhtNodes: 0, vpn: vpn)
  t.vpnHeldReason = reason
  return t
}

// MARK: The words for each hold

@Suite struct HeldWordingTests {
  private func summary(_ reason: Components.Schemas.VpnHeldReason?) -> VpnSummary {
    VpnSummary(transfer: transfer(.held, reason: reason), status: nil, connection: .live)
  }

  @Test func noVpnYet() throws {
    let s = summary(.noVpnYet)
    #expect(s.pill.title == "Held: no VPN yet")
    #expect(s.pill.help == "No VPN is set up yet, so every torrent is held. Click for details.")
    #expect(s.details.title == "Held: no VPN yet")
    #expect(s.details.sentence.hasPrefix("No VPN is set up yet, so torrents are held"))
    let banner = try #require(StatusBanner.list(transfer: transfer(.held, reason: .noVpnYet)).first)
    #expect(
      banner.message
        == "No VPN is set up yet: all torrents are stopped until you add one or choose to start without it."
    )
    #expect(banner.actions.map(\.title) == ["Open VPN Settings…", "Start Without VPN…"])
    #expect(s.details.offersVpnSettings && s.details.startWithout != nil)
  }

  @Test func vpnRemoved() throws {
    let s = summary(.vpnRemoved)
    #expect(s.pill.title == "Held: VPN removed")
    #expect(s.details.title == "Held: VPN removed")
    #expect(s.details.sentence.hasPrefix("The VPN was removed, so torrents are held"))
    let banner = try #require(
      StatusBanner.list(transfer: transfer(.held, reason: .vpnRemoved)).first)
    #expect(banner.message.hasPrefix("The VPN was removed: all torrents are stopped"))
    #expect(banner.actions.map(\.title) == ["Open VPN Settings…", "Start Without VPN…"])
    #expect(s.details.startWithout != nil)
  }

  @Test func vpnUnusableNeverOffersStartWithout() throws {
    let s = summary(.vpnUnusable)
    #expect(s.pill.title == "Held: VPN can't be used")
    #expect(s.details.sentence.contains("Fix or replace it"))
    let banner = try #require(
      StatusBanner.list(transfer: transfer(.held, reason: .vpnUnusable)).first)
    #expect(
      banner.message
        == "The saved VPN can't be used: all torrents are stopped until you fix or replace it.")
    #expect(banner.actions == [.openVpnSettings])
    #expect(s.details.offersVpnSettings && s.details.startWithout == nil)
  }

  @Test func anOlderUmbraWithNoReasonKeepsTodaysWords() throws {
    let s = summary(nil)
    #expect(s.pill.title == "VPN held")
    #expect(s.pill.help == "The VPN was removed, so every torrent is held. Click for details.")
    #expect(s.details.title == "VPN removed")
    #expect(
      s.details.sentence
        == "The VPN was removed, so every torrent is held and your own address is never exposed.")
    let banner = try #require(StatusBanner.list(transfer: transfer(.held)).first)
    #expect(
      banner.message
        == "The VPN was removed: all torrents are stopped until you set one up or choose to start without it."
    )
    // Its only hold was a removed VPN, which starting without one releases.
    #expect(s.details.startWithout != nil)
  }

  @Test func theReasonFromGetVpnIsUsedWhenTheFeedHasNone() {
    var status = Components.Schemas.VpnStatus(
      state: .held, configured: true, saved: [], failover: .init(enabled: false, minutes: 5))
    status.heldReason = .vpnUnusable
    let s = VpnSummary(transfer: transfer(.held), status: status, connection: .live)
    #expect(s.pill.title == "Held: VPN can't be used")
  }

  @Test func onlyHoldsItReleasesOfferStartWithout() {
    for state: Components.Schemas.VpnState in [.connected, .connecting, .down, .none] {
      #expect(
        VpnSummary(transfer: transfer(state), status: nil, connection: .live).details
          .startWithout == nil)
    }
    // Down and none point at Settings; connected and connecting don't need to.
    #expect(
      VpnSummary(transfer: transfer(.down), status: nil, connection: .live).details
        .offersVpnSettings)
    #expect(
      !VpnSummary(transfer: transfer(.connected), status: nil, connection: .live).details
        .offersVpnSettings)
  }

  @Test func theConfirmationSaysPeersSeeTheRealAddress() throws {
    let question = try #require(StartWithoutVpnConfirmation(HeldWords(reason: .noVpnYet)))
    #expect(question.title == "Start without a VPN?")
    #expect(question.message.contains("every peer will see its real IP address"))
    #expect(question.cancelButton == "Cancel")
    #expect(question.startButton == "Start Without VPN")
    #expect(StartWithoutVpnConfirmation(HeldWords(reason: .vpnUnusable)) == nil)
  }

  /// The VPN page: what is true when no VPN is saved.
  @MainActor @Test func thePageSaysWhyNoVpnIsInUse() {
    func status(_ state: Components.Schemas.VpnState, _ reason: Components.Schemas.VpnHeldReason?)
      -> Components.Schemas.VpnStatus
    {
      var s = Components.Schemas.VpnStatus(
        state: state, configured: false, saved: [], failover: .init(enabled: false, minutes: 5))
      s.heldReason = reason
      return s
    }
    let noneYet = VpnSettingsModel(
      fixture: status(.held, .noVpnYet), transfer: transfer(.held, reason: .noVpnYet))
    #expect(noneYet.noVpnSituation == .held(HeldWords(reason: .noVpnYet)))
    #expect(noneYet.startWithout != nil)
    let removed = VpnSettingsModel(
      fixture: status(.held, .vpnRemoved), transfer: transfer(.held, reason: .vpnRemoved))
    #expect(removed.noVpnSituation == .held(HeldWords(reason: .vpnRemoved)))
    let chosen = VpnSettingsModel(fixture: status(.none, nil), transfer: transfer(.none))
    #expect(chosen.noVpnSituation == .runningWithout)
    #expect(
      noneYet.noVpnSituation?.text.hasPrefix("Torrents are held because no VPN is set up yet")
        == true)
    #expect(
      removed.noVpnSituation?.text.hasPrefix("Torrents are held because the VPN was removed")
        == true)
    #expect(chosen.noVpnSituation?.text.contains("you chose to run without one") == true)
    #expect(chosen.startWithout == nil)
  }
}
