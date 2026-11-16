import Foundation
import UmbraAPI

/// What the app says about a hold, by the reason Umbra gives for it.
///
/// "Held" means Umbra keeps every torrent stopped and touches nothing on
/// the network. Umbra says why (`VpnHeldReason`), and each reason needs
/// different words: a Mac that never had a VPN wasn't "removed", and a
/// saved VPN that can't be used can't be released by "Start without VPN".
/// The words come from Umbra's web page (`web/src/lib/held.ts`), with
/// "Settings → VPN" for its links.
///
/// An older Umbra sends no reason; then the words are the ones the app
/// always used, which assumed the VPN had been removed (the only hold an
/// older Umbra has).
public struct HeldWords: Equatable, Sendable {
  /// The pill's words and the popover's heading.
  public let title: String
  /// The line above the torrent list.
  public let banner: String
  /// The popover's sentence (and the VPN page's status line).
  public let detail: String
  /// The pill's tooltip.
  public let help: String
  /// Why "Start Without VPN" would be chosen, said in its confirmation; nil
  /// where starting without a VPN does nothing (a saved VPN that can't be
  /// used stays held until it is fixed), so the button isn't offered.
  public let startWithout: String?

  /// Whether "Start Without VPN…" is offered for this hold.
  public var offersStartWithout: Bool { startWithout != nil }

  public init(reason: Components.Schemas.VpnHeldReason?) {
    switch reason {
    case .noVpnYet:
      title = "Held: no VPN yet"
      banner =
        "No VPN is set up yet: all torrents are stopped until you add one or choose to start "
        + "without it."
      detail =
        "No VPN is set up yet, so torrents are held and nothing has gone out to the network. "
        + "Add a VPN, or start without one."
      help = "No VPN is set up yet, so every torrent is held. Click for details."
      startWithout = "Torrents are held because no VPN is set up yet."
    case .vpnRemoved:
      title = "Held: VPN removed"
      banner =
        "The VPN was removed: all torrents are stopped until you add one or choose to start "
        + "without it."
      detail =
        "The VPN was removed, so torrents are held and your real IP address is never exposed."
      help = "The VPN was removed, so every torrent is held. Click for details."
      startWithout = "Torrents are held because the VPN was removed."
    case .vpnUnusable:
      title = "Held: VPN can't be used"
      banner =
        "The saved VPN can't be used: all torrents are stopped until you fix or replace it."
      detail =
        "The saved VPN can't be used, so torrents are held and your real IP address is never "
        + "exposed. Fix or replace it in Settings → VPN."
      help = "The saved VPN can't be used, so every torrent is held. Click for details."
      startWithout = nil
    case nil:
      // An older Umbra: its only hold was a removed VPN. Today's words.
      title = "VPN held"
      banner =
        "The VPN was removed: all torrents are stopped until you set one up "
        + "or choose to start without it."
      detail =
        "The VPN was removed, so every torrent is held and your own address is never exposed."
      help = "The VPN was removed, so every torrent is held. Click for details."
      startWithout = "Torrents are held because the VPN was removed."
    }
  }
}

/// The question asked before "Start Without VPN" does anything. It is
/// always asked, Cancel is the button Return presses, and it says plainly
/// what happens: peers see this Mac's real address. The app never starts
/// without a VPN by itself; Umbra does, and only when asked.
public struct StartWithoutVpnConfirmation: Equatable, Sendable {
  public let title = "Start without a VPN?"
  public let message: String
  public let cancelButton = "Cancel"
  public let startButton = "Start Without VPN"

  /// Nil where starting without a VPN does nothing (see `HeldWords`).
  public init?(_ words: HeldWords) {
    guard let why = words.startWithout else { return nil }
    message =
      why + " If you start without one, torrents run on this Mac's own connection and "
      + "every peer will see its real IP address. Umbra remembers this choice; adding a VPN "
      + "later in Settings → VPN puts torrents behind it again."
  }
}
