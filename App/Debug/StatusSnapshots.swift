#if DEBUG
  import SwiftUI
  import UmbraAPI
  import UmbraKit

  /// Pictures of the VPN pill and its popover in each state, the list with
  /// each banner (and two at once), and each session state. The toolbar's
  /// glass draws blank offscreen, so the pill is drawn as a plain view.
  /// All values are made up.
  @MainActor
  enum StatusSnapshots {
    static var entries: [SnapshotEntry] {
      vpnEntries + bannerEntries + sessionEntries
    }

    // MARK: The pill and its popover

    private static let vpnStates: [(String, Components.Schemas.VpnState)] = [
      ("connected", .connected), ("connecting", .connecting), ("down", .down), ("held", .held),
      ("none", .none),
    ]

    private static var vpnEntries: [SnapshotEntry] {
      var list = vpnStates.map { name, state in
        SnapshotEntry(name: "vpn-\(name)", size: CGSize(width: 340, height: 250)) {
          AnyView(VpnSnapshotView(summary: summary(state)))
        }
      }
      // Held, for each reason Umbra gives (and an older Umbra's none,
      // which is "vpn-held" above).
      for (name, reason) in heldReasons {
        list.append(
          SnapshotEntry(name: "vpn-held-\(name)", size: CGSize(width: 340, height: 250)) {
            AnyView(
              VpnSnapshotView(
                summary: VpnSummary(
                  transfer: transfer(.held, heldReason: reason), status: status(.held),
                  connection: .live, now: Fixtures.now)))
          })
      }
      // Umbra not answering: the state isn't claimed.
      list.append(
        SnapshotEntry(name: "vpn-unknown", size: CGSize(width: 340, height: 250)) {
          AnyView(
            VpnSnapshotView(
              summary: VpnSummary(
                transfer: transfer(.connected), status: status(.connected),
                connection: .reconnecting(since: Fixtures.now), now: Fixtures.now)))
        })
      // Just after the Mac woke: a "connected" from before the sleep isn't claimed.
      list.append(
        SnapshotEntry(name: "vpn-after-wake", size: CGSize(width: 340, height: 250)) {
          AnyView(
            VpnSnapshotView(
              summary: VpnSummary(
                transfer: transfer(.connected), status: status(.connected),
                connection: .live, now: Fixtures.now, waking: true)))
        })
      return list
    }

    private static func summary(_ state: Components.Schemas.VpnState) -> VpnSummary {
      VpnSummary(
        transfer: transfer(state), status: status(state), connection: .live, now: Fixtures.now)
    }

    static let heldReasons: [(String, Components.Schemas.VpnHeldReason)] = [
      ("no-vpn-yet", .noVpnYet), ("removed", .vpnRemoved), ("unusable", .vpnUnusable),
    ]

    static func transfer(
      _ vpn: Components.Schemas.VpnState, engineProblem: Components.Schemas.EngineProblem? = nil,
      freeSpace: Int64 = 412 << 30, heldReason: Components.Schemas.VpnHeldReason? = nil
    ) -> Components.Schemas.Transfer {
      var t = Fixtures.feed().transfer!
      t.vpn = vpn
      t.vpnHeldReason = heldReason
      t.vpnIp = vpn == .connected ? "185.213.4.22" : nil
      t.engineProblem = engineProblem
      t.freeSpace = freeSpace
      return t
    }

    static func status(_ state: Components.Schemas.VpnState) -> Components.Schemas.VpnStatus {
      var s = Components.Schemas.VpnStatus(
        state: state, configured: state != .none,
        saved: state == .none ? [.init(id: "a", name: "AirVPN Zurich", inUse: true)] : [],
        failover: .init(enabled: false, minutes: 5))
      s.since = Fixtures.now.addingTimeInterval(-47 * 60)
      switch state {
      case .connected:
        s.saved = [.init(id: "a", name: "AirVPN Zurich", inUse: true)]
        s.vpnIp = "185.213.4.22"
        s.realIp = "203.0.113.9"
        s.forwardedPort = 51413
      case .none:
        s.saved = []
        s.realIp = "203.0.113.9"
        s.since = nil
      case .down:
        s.message = "The tunnel stopped answering 3 minutes ago."
      case .connecting, .held:
        break
      }
      return s
    }

    // MARK: Banners

    private static var bannerEntries: [SnapshotEntry] {
      let size = CGSize(width: 900, height: 360)
      let port = Components.Schemas.EngineProblem(
        message: "the engine can't listen on TCP port 6881 (is something else using it?)",
        portBusy: true)
      let held = heldReasons.map { name, reason in
        SnapshotEntry(name: "banner-vpn-held-\(name)", size: size) {
          pane(transfer(.held, heldReason: reason))
        }
      }
      return held + [
        SnapshotEntry(name: "banner-vpn-down", size: size) {
          pane(transfer(.down))
        },
        SnapshotEntry(name: "banner-vpn-held", size: size) {
          pane(transfer(.held))
        },
        SnapshotEntry(name: "banner-engine", size: size) {
          pane(transfer(.connected, engineProblem: port))
        },
        SnapshotEntry(name: "banner-disk", size: size) {
          pane(transfer(.connected, freeSpace: 4 << 30))
        },
        SnapshotEntry(name: "banner-two", size: size) {
          pane(transfer(.down, freeSpace: 4 << 30))
        },
        SnapshotEntry(name: "banner-reconnecting", size: size) {
          pane(transfer(.connected), note: "Reconnecting…")
        },
      ]
    }

    private static func pane(_ transfer: Components.Schemas.Transfer, note: String? = nil)
      -> AnyView
    {
      var feed = Fixtures.feed()
      feed.transfer = transfer
      let store = TorrentStore.fixture(feed)
      let model = Fixtures.model(store)
      return AnyView(
        TorrentListPane(
          model: model, statusBar: Fixtures.statusBar(), loaded: true, tableAutosaveName: nil,
          banners: StatusBanner.list(transfer: transfer), connectionNote: note))
    }

    // MARK: Session states

    private static var sessionEntries: [SnapshotEntry] {
      let size = CGSize(width: 640, height: 360)
      let phases: [(String, AppSession.Phase)] = [
        ("starting", .starting), ("reconnecting", .reconnecting(attempt: 2)),
        ("saving", .saving),
        (
          "failed",
          .failed(
            message:
              "Umbra's server stopped while starting (exit code 1). The end of its log is below.",
            logTail: [
              "umbra 1.4.0 starting", "opening /Users/alex/Library/Application Support/Umbra",
              "the engine can't start: port 6881 in use",
            ])
        ),
      ]
      return phases.map { name, phase in
        SnapshotEntry(name: "session-\(name)", size: size) {
          AnyView(SessionStateView(phase: phase))
        }
      }
    }
  }

  /// The pill, with its popover's contents drawn under it.
  private struct VpnSnapshotView: View {
    let summary: VpnSummary

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        VpnPillContent(pill: summary.pill)
          .padding(.horizontal, 12).padding(.vertical, 6)
          .background(.quaternary.opacity(0.5), in: .capsule)
        VpnPopoverView(details: summary.details, onCheckAgain: {})
          .background(.regularMaterial, in: .rect(cornerRadius: 10))
          .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
      }
      .padding(16)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }
#endif
