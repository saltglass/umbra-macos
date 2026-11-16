import Foundation
import UmbraAPI

/// A line above the list saying something needs attention. The rules, the
/// words and the order follow the web page (`web/src/components/shell/Banners.tsx`):
/// the engine can't run, then the VPN down or held, then the disk nearly
/// full. The web page shows only the first that applies; the Mac window
/// stacks all that apply, most important first.
///
/// All come from the live feed's "transfer" message. There is no banner for
/// a VPN that is merely connecting, as on the web page (the pill shows it).
public struct StatusBanner: Equatable, Sendable, Identifiable {
  public enum Kind: Sendable, Equatable {
    case engineProblem, vpnDown, vpnHeld, lowSpace
  }

  /// What a banner's button does. Only things that work today.
  public enum Action: Sendable, Equatable {
    /// Ask Umbra to look at the VPN again (`TorrentActions.checkVpnAgain`).
    case checkAgain
    /// Open the Settings window on its VPN page.
    case openVpnSettings
    /// Ask Umbra to run without a VPN. The app always asks the person
    /// first, with these words (see `StartWithoutVpnConfirmation`).
    case startWithoutVpn(StartWithoutVpnConfirmation)

    public var title: String {
      switch self {
      case .checkAgain: "Check Again"
      case .openVpnSettings: "Open VPN Settings…"
      case .startWithoutVpn: "Start Without VPN…"
      }
    }
  }

  public let kind: Kind
  public var id: Kind { kind }
  /// An SF Symbol.
  public let symbol: String
  public let message: String
  public let role: ColorRole
  /// Its buttons, in order; none for some.
  public let actions: [Action]
  /// None can be closed: like the web page's, each stays while its
  /// trouble does, and goes by itself when Umbra says it is over.
  public let isDismissible = false

  /// The banners that apply to these totals, most important first.
  /// `waking`: the Mac just woke and Umbra is being asked afresh
  /// (`WakeRecovery`); a "VPN down" from then may be a moment old or about
  /// to pass, so the pill's "Checking VPN…" says it instead of a banner.
  public static func list(
    transfer: Components.Schemas.Transfer?, waking: Bool = false
  ) -> [StatusBanner] {
    guard let transfer else { return [] }
    var banners: [StatusBanner] = []
    if let problem = transfer.engineProblem {
      banners.append(
        StatusBanner(
          kind: .engineProblem, symbol: "xmark.octagon.fill",
          message: "Every torrent is stopped: \(problem.message)", role: .red, actions: []))
    }
    switch transfer.vpn {
    case .down where !waking:
      banners.append(
        StatusBanner(
          kind: .vpnDown, symbol: "exclamationmark.shield.fill",
          message: "VPN is down: all torrents are stopped until it reconnects.", role: .red,
          actions: [.checkAgain, .openVpnSettings]))
    case .held:
      // The words depend on why (no VPN yet, removed, can't be used). There
      // is nothing to check again while held, as on the popover; "Start
      // Without VPN…" only where it releases the hold.
      let words = HeldWords(reason: transfer.vpnHeldReason)
      var actions: [Action] = [.openVpnSettings]
      if let question = StartWithoutVpnConfirmation(words) {
        actions.append(.startWithoutVpn(question))
      }
      banners.append(
        StatusBanner(
          kind: .vpnHeld, symbol: "exclamationmark.shield.fill", message: words.banner,
          role: .red, actions: actions))
    case .connected, .connecting, .down, .none:
      break
    }
    // A negative free space means Umbra can't tell; a low-space level of 0
    // is "never warn".
    if transfer.freeSpace >= 0, transfer.lowSpace > 0, transfer.freeSpace < transfer.lowSpace {
      banners.append(
        StatusBanner(
          kind: .lowSpace, symbol: "exclamationmark.triangle.fill",
          message: "Disk almost full: \(Format.bytes(transfer.freeSpace)) free.", role: .orange,
          actions: []))
    }
    return banners
  }
}
