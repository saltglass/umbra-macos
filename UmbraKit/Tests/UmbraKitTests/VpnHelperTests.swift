import CryptoKit
import Foundation
import Testing
import UmbraAPI

@testable import UmbraKit

/// The hold the real app starts with, against a real Umbra on 127.0.0.1
/// in a temporary folder. Nothing here reaches a VPN provider: the one VPN
/// added is made up in the test, with keys made on the spot and a server
/// address of 127.0.0.1 on a port nothing listens on.
extension HelperIntegrationTests {
  /// With the hold on (as in the real app), a new install is held because
  /// no VPN is set up yet; "Start without VPN" releases it; and after a
  /// restart on the same folder it stays released (Umbra remembers).
  @Test func aNewInstallIsHeldUntilTheChoiceIsMadeAndRemembersIt() async throws {
    try await withSupervisor(holdUntilVpn: true) { supervisor, _ in
      let first = SettingsActions(connection: try await supervisor.start())
      let held = try await first.vpn()
      #expect(held.state == .held)
      #expect(held.heldReason == .noVpnYet)
      #expect(!held.configured)
      // The app's words for it.
      #expect(HeldWords(reason: held.heldReason).title == "Held: no VPN yet")

      try await first.startWithoutVpn()
      #expect(await eventually { (try? await first.vpn().state) == VpnState.none })

      await supervisor.stop()
      let second = SettingsActions(connection: try await supervisor.start())
      let after = try await second.vpn()
      #expect(after.state != .held)
      #expect(after.heldReason == nil)
    }
  }

  /// While held, a torrent's web address is refused before anything is
  /// fetched, in words the Add sheet can show as they are. (The address
  /// is one that can never exist: `.invalid` is reserved for that.)
  @Test func whileHeldAWebAddressIsRefusedInPlainWords() async throws {
    try await withSupervisor(holdUntilVpn: true) { supervisor, _ in
      let actions = TorrentActions(connection: try await supervisor.start())
      let error = await #expect(throws: UmbraError.self) {
        _ = try await actions.inspect(.url("https://example.invalid/file.torrent"))
      }
      // What the Add sheet shows (Umbra names the address field).
      let shown = await MainActor.run { error.map { AddTorrentModel.words(for: $0) } }
      #expect(
        shown
          == "No VPN is set up yet, so nothing is downloaded: add a VPN in Settings → VPN, "
          + "or choose to start without one, then add the address again.")
    }
  }

  /// Adding a VPN through the page's model releases the hold; a broken
  /// configuration is refused with Umbra's words; and the configuration
  /// is nowhere in the model afterwards.
  @Test func addingAVpnReleasesTheHoldAndLeavesNoCopy() async throws {
    try await withSupervisor(holdUntilVpn: true) { supervisor, _ in
      try await Self.addAVpn(on: try await supervisor.start())
    }
  }

  @MainActor static func addAVpn(on connection: Connection) async throws {
    let source = FakeVpnSource()
    source.settingsActions = SettingsActions(connection: connection)
    let model = VpnSettingsModel(source: source)
    #expect(await eventually { model.phase == .loaded })
    #expect(model.noVpnSituation == .held(HeldWords(reason: .noVpnYet)))

    // Not a WireGuard file at all: refused, and nothing is saved.
    var broken = VpnPasteDraft()
    broken.text = "this is not a configuration"
    let refusal = try #require(await model.add(broken))
    #expect(!VpnSettingsModel.explanation(for: refusal).isEmpty)
    #expect(model.saved.isEmpty)

    // A made-up one: fresh keys, a server on 127.0.0.1 where nothing listens.
    let config = Self.madeUpConfiguration()
    let privateKey = try #require(config.privateKey)
    var draft = VpnPasteDraft(name: "Example VPN One")
    draft.text = config.text
    #expect(await model.add(draft) == nil)
    #expect(model.saved.map(\.name) == ["Example VPN One"])
    #expect(model.status?.state != .held)

    // Nothing of the configuration is left in the model, or in what it prints.
    var dumped = ""
    dump(model, to: &dumped)
    for text in [dumped, String(describing: model), String(reflecting: model.status)] {
      #expect(!text.contains(privateKey))
    }
  }
}

extension HelperIntegrationTests {
  /// A WireGuard configuration made up for a test: keys made on the spot,
  /// thrown away after, and a server address of 127.0.0.1 on a port
  /// nothing listens on (the helper is loopback-only anyway).
  static func madeUpConfiguration() -> (text: String, privateKey: String?) {
    let mine = Curve25519.KeyAgreement.PrivateKey()
    let server = Curve25519.KeyAgreement.PrivateKey().publicKey
    let privateKey = mine.rawRepresentation.base64EncodedString()
    let text = """
      [Interface]
      PrivateKey = \(privateKey)
      Address = 10.66.0.2/32

      [Peer]
      PublicKey = \(server.rawRepresentation.base64EncodedString())
      AllowedIPs = 0.0.0.0/0
      Endpoint = 127.0.0.1:9
      """
    return (text, privateKey)
  }
}

/// A stand-in for `AppSession` for the VPN page's model: a connection
/// tests set by hand, settings-change notices, and the feed's totals.
@MainActor @Observable
final class FakeVpnSource: VpnSettingsSource {
  var settingsActions: SettingsActions?
  var liveTransfer: Components.Schemas.Transfer?
  var liveConnection: FeedConnectionState = .live
  let store = TorrentStore()

  func listenForSettingsChanges(
    _ listener: @escaping @MainActor (String) -> Void
  ) -> SettingsSubscription {
    store.listenForSettingsChanges(listener)
  }
}

typealias VpnState = Components.Schemas.VpnState
