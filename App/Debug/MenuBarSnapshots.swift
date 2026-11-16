#if DEBUG
  import SwiftUI
  import UmbraAPI
  import UmbraKit

  /// Pictures of the menu bar panel: busy, VPN held, VPN down, nothing
  /// active and not running. The panel is drawn on a material under it, as
  /// macOS draws it. All values are made up.
  @MainActor
  enum MenuBarSnapshots {
    static var entries: [SnapshotEntry] {
      [
        entry("menubar-busy", height: 680, summary(busy)),
        entry("menubar-vpn-held", height: 460, summary(busy, vpn: .held, heldReason: .noVpnYet)),
        entry("menubar-vpn-down", height: 460, summary(busy, vpn: .down)),
        entry("menubar-many", height: 720, summary(busy + extraDownloads)),
        entry("menubar-nothing-active", height: 460, summary(quiet)),
        entry("menubar-not-running", height: 280, notRunning),
        entry(
          "menubar-failure", height: 740,
          summary(busy),
          failure: "Couldn't pause 12 torrents. Umbra is busy. Try again in a moment."),
      ]
    }

    private static func entry(
      _ name: String, height: CGFloat, _ summary: MenuBarSummary, failure: String? = nil
    ) -> SnapshotEntry {
      SnapshotEntry(name: name, size: CGSize(width: 340, height: height)) {
        AnyView(
          MenuBarPanelView(summary: summary, failure: failure, actions: MenuBarPanelActions())
            .fixedSize(horizontal: false, vertical: true)
            .background(.regularMaterial, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 8))
      }
    }

    // MARK: Made-up data

    private static func torrent(
      _ hash: String, _ name: String, _ state: Components.Schemas.TorrentState,
      speed: Int64 = 0, eta: Int64? = nil, progress: Double = 0
    ) -> Components.Schemas.Torrent {
      var t = Components.Schemas.Torrent(
        hash: hash, name: name, size: 8 << 30, progress: progress, state: state,
        downSpeed: speed, upSpeed: 0, ratio: 0, category: "", tags: [], addedAt: Fixtures.now,
        savePath: "/Downloads", seeds: 0, seedsTotal: 0, peers: 0, peersTotal: 0, downloaded: 0,
        uploaded: 0, seedTimeSeconds: 0, queuePosition: 0)
      t.etaSeconds = eta
      return t
    }

    private static let busy: [Components.Schemas.Torrent] = [
      torrent(
        "a1", "ubuntu-26.04-desktop-amd64.iso", .downloading, speed: 6_400_000, eta: 540,
        progress: 0.62),
      torrent(
        "a2", "Big Buck Bunny (2008) 2160p Open Movie Project Release Group", .downloading,
        speed: 1_900_000, eta: 7_800, progress: 0.18),
      torrent(
        "a3", "Public Domain Radio Archive 1930-1955", .downloading, speed: 300_000,
        eta: 93_000, progress: 0.05),
      torrent("a4", "Debian netinst", .downloading, speed: 0, eta: nil, progress: 0.9),
      torrent("a5", "Sintel", .downloading, speed: 120_000, eta: 2_400, progress: 0.44),
      torrent("s1", "Linux ISOs 2025", .seeding),
      torrent("s2", "Open textbooks", .seeding),
      torrent("s3", "Wikipedia dump", .seeding),
      torrent("s4", "Field recordings", .seeding),
      torrent("s5", "Map tiles", .seeding),
      torrent("s6", "Old photos", .seeding),
      torrent("p1", "Paused thing", .paused, progress: 0.3),
    ]

    private static let extraDownloads = (6...8).map {
      torrent("x\($0)", "Extra download \($0)", .downloading, speed: Int64($0) * 1_000)
    }

    private static let quiet = [
      torrent("s1", "Linux ISOs 2025", .paused), torrent("s2", "Open textbooks", .paused),
    ]

    private static func summary(
      _ torrents: [Components.Schemas.Torrent], vpn: Components.Schemas.VpnState = .connected,
      heldReason: Components.Schemas.VpnHeldReason? = nil
    ) -> MenuBarSummary {
      let down = torrents.reduce(Int64(0)) { $0 + $1.downSpeed }
      var transfer = StatusSnapshots.transfer(vpn, heldReason: heldReason)
      transfer.downSpeed = vpn == .connected ? down : 0
      transfer.upSpeed = vpn == .connected && !torrents.isEmpty ? 1_300_000 : 0
      transfer.slowMode = false
      return MenuBarSummary(
        torrents: vpn == .connected ? torrents : torrents.map(held),
        transfer: transfer, phase: .running, feed: .live,
        vpn: VpnSummary(
          transfer: transfer, status: StatusSnapshots.status(vpn), connection: .live,
          now: Fixtures.now),
        slowMode: false)
    }

    /// A torrent as Umbra shows it while the VPN stops everything.
    private static func held(_ t: Components.Schemas.Torrent) -> Components.Schemas.Torrent {
      var copy = t
      if copy.state == .downloading || copy.state == .seeding { copy.state = .waitingForVpn }
      copy.downSpeed = 0
      return copy
    }

    private static var notRunning: MenuBarSummary {
      MenuBarSummary(
        torrents: [], transfer: nil, phase: .stopped, feed: .connecting,
        vpn: VpnSummary(transfer: nil, status: nil, connection: .connecting),
        slowMode: false)
    }
  }
#endif
