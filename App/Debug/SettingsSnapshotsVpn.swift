#if DEBUG
  import SwiftUI
  import UmbraAPI
  import UmbraKit

  /// Pictures of Settings → VPN and its sheets. Everything is made up:
  /// "Example VPN" names and addresses from the documentation ranges
  /// (192.0.2.x, 198.51.100.x, 203.0.113.x). No configuration appears in
  /// any picture: the paste sheet's text area is always empty.
  @MainActor
  enum SettingsSnapshotsVpn {
    static let tall = CGSize(width: SettingsMetrics.width, height: 860)
    static let short = CGSize(width: SettingsMetrics.width, height: 560)
    static let sheet = CGSize(width: 500, height: 420)

    typealias Status = Components.Schemas.VpnStatus

    static func transfer(
      _ vpn: Components.Schemas.VpnState, reason: Components.Schemas.VpnHeldReason? = nil
    ) -> Components.Schemas.Transfer {
      var t = Fixtures.feed().transfer!
      t.vpn = vpn
      t.vpnHeldReason = reason
      t.vpnIp = vpn == .connected ? "198.51.100.7" : nil
      return t
    }

    /// Connected through the first of three saved VPNs, switching on.
    static var connected: Status {
      var s = Status(
        state: .connected, configured: true,
        saved: [
          .init(
            id: "one", name: "Example VPN One", inUse: true, endpoint: "203.0.113.10:51820",
            forwardedPort: 51413),
          .init(id: "two", name: "Example VPN Two", inUse: false, endpoint: "198.51.100.20:51820"),
          .init(
            id: "three", name: "Example VPN Three", inUse: false,
            endpoint: "203.0.113.30:51820"),
        ],
        failover: .init(enabled: true, minutes: 5))
      s.vpnIp = "198.51.100.7"
      s.realIp = "192.0.2.44"
      s.forwardedPort = 51413
      s.since = Fixtures.now.addingTimeInterval(-47 * 60)
      return s
    }

    static func held(_ reason: Components.Schemas.VpnHeldReason) -> Status {
      var s = Status(
        state: .held, configured: false, saved: [], failover: .init(enabled: false, minutes: 5))
      s.heldReason = reason
      return s
    }

    /// Running on the Mac's own connection, by choice.
    static var without: Status {
      var s = Status(
        state: .none, configured: false, saved: [], failover: .init(enabled: false, minutes: 5))
      s.realIp = "192.0.2.44"
      return s
    }

    /// One saved VPN whose configuration can't be read.
    static var unusable: Status {
      var s = Status(
        state: .held, configured: true,
        saved: [
          .init(
            id: "one", name: "Example VPN One", inUse: true,
            problem: "Its configuration can't be read: Umbra's secret key has changed.")
        ],
        failover: .init(enabled: false, minutes: 5))
      s.heldReason = .vpnUnusable
      s.message = "The saved VPN can't be used: Umbra's secret key has changed."
      return s
    }

    static func page(_ status: Status, _ transfer: Components.Schemas.Transfer) -> AnyView {
      AnyView(
        VpnPage(model: VpnSettingsModel(fixture: status, transfer: transfer, now: Fixtures.now)))
    }

    static let configRefusal = UmbraError(
      code: "invalid", message: "Some fields need attention.",
      fields: ["config": "This isn't a WireGuard configuration: it has no [Interface] section."])

    static var entries: [SnapshotEntry] {
      [
        SnapshotEntry(name: "settings-vpn-connected", size: tall) {
          page(connected, transfer(.connected))
        },
        SnapshotEntry(name: "settings-vpn-none-held", size: short) {
          page(held(.noVpnYet), transfer(.held, reason: .noVpnYet))
        },
        SnapshotEntry(name: "settings-vpn-removed-held", size: short) {
          page(held(.vpnRemoved), transfer(.held, reason: .vpnRemoved))
        },
        SnapshotEntry(name: "settings-vpn-without", size: short) {
          page(without, transfer(.none))
        },
        SnapshotEntry(name: "settings-vpn-unusable", size: tall) {
          page(unusable, transfer(.held, reason: .vpnUnusable))
        },
        SnapshotEntry(name: "settings-vpn-paste", size: sheet) {
          AnyView(VpnPasteSheet(model: VpnSettingsModel(fixture: connected)))
        },
        SnapshotEntry(name: "settings-vpn-paste-refused", size: sheet) {
          AnyView(
            VpnPasteSheet(model: VpnSettingsModel(fixture: connected), refusal: configRefusal))
        },
        SnapshotEntry(name: "settings-vpn-edit", size: CGSize(width: 500, height: 360)) {
          AnyView(
            VpnEditSheet(model: VpnSettingsModel(fixture: connected), vpn: connected.saved[0]))
        },
        SnapshotEntry(
          name: "settings-vpn-not-connected",
          size: CGSize(width: SettingsMetrics.width, height: 300)
        ) {
          AnyView(VpnPage(model: VpnSettingsModel(fixture: nil, phase: .notConnected)))
        },
      ]
    }
  }
#endif
