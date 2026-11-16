import Foundation
import UmbraAPI

/// What the toolbar's VPN pill and its popover say, worked out from what
/// Umbra reports. Umbra decides the VPN's state; this only finds the words,
/// the symbol and the colour role for it. It never decides anything itself.
///
/// Two sources are read, and they can briefly disagree:
/// - the live feed's "transfer" message, sent about once a second;
/// - `GET /vpn` (`AppSession.vpnStatus`), asked for every 30 seconds, which
///   carries the details (forwarded port, when it changed, the real address).
///
/// **The feed wins for the state**, because it is the fresher of the two: a
/// VPN that just dropped shows within a second, not up to half a minute
/// later. The details from `GET /vpn` are used only while that answer
/// names the same state as the feed: an address or a "since" that belongs
/// to a different state would be wrong to show next to this one.
///
/// While the feed itself is not open (Umbra stopped answering) the state is
/// shown as unknown rather than as the last thing heard: a "connected" that
/// is minutes old must never look like a promise.
///
/// For the same reason, just after the Mac wakes from sleep (`waking`, from
/// `WakeRecovery`) a VPN state is shown as "Checking VPN…" until Umbra has
/// answered afresh. "Held" and "No VPN" are shown as they are: a sleep
/// doesn't change them.
public struct VpnSummary: Equatable, Sendable {
  public let pill: VpnPill
  public let details: VpnDetails

  public init(
    transfer: Components.Schemas.Transfer?, status: Components.Schemas.VpnStatus?,
    connection: FeedConnectionState, now: Date = Date(), locale: Locale = .current,
    waking: Bool = false
  ) {
    let state = Self.state(transfer: transfer, status: status, connection: connection)
    // The details are only trusted when they describe the state shown.
    let agreeing = state.flatMap { $0 == status?.state ? status : nil }
    if waking, Self.sleepCanChange(state) {
      pill = .afterWake
      details = .afterWake
      return
    }
    switch state {
    case nil:
      let heardBefore = transfer != nil || status != nil
      pill = .unknown(checking: !heardBefore)
      details = .unknown(checking: !heardBefore)
    case .some(let state):
      let address = Self.address(state: state, transfer: transfer, agreeing: agreeing)
      let held = state == .held ? HeldWords(reason: Self.heldReason(transfer, agreeing)) : nil
      pill = VpnPill(state: state, address: address, held: held)
      details = VpnDetails(
        state: state, address: address, held: held, agreeing: agreeing, now: now, locale: locale)
    }
  }

  /// The state to show, nil when it isn't known right now.
  static func state(
    transfer: Components.Schemas.Transfer?, status: Components.Schemas.VpnStatus?,
    connection: FeedConnectionState
  ) -> Components.Schemas.VpnState? {
    // A feed that isn't open can't be trusted, and neither can an old
    // `GET /vpn` answer, as it comes from the same Umbra.
    guard connection == .live else { return nil }
    return transfer?.vpn ?? status?.state
  }

  /// Whether a sleep can have made this state out of date: any VPN state
  /// (and an unknown one), but not "held" or "No VPN".
  static func sleepCanChange(_ state: Components.Schemas.VpnState?) -> Bool {
    switch state {
    case .some(.held), .some(.none): false
    case .some(.connected), .some(.connecting), .some(.down), nil: true
    }
  }

  /// Why Umbra holds the torrents: the feed's reason first (it is the
  /// fresher), else the one `GET /vpn` gave for the same state. Nil from an
  /// older Umbra that sends none.
  static func heldReason(
    _ transfer: Components.Schemas.Transfer?, _ agreeing: Components.Schemas.VpnStatus?
  ) -> Components.Schemas.VpnHeldReason? {
    if transfer?.vpn == .held, let reason = transfer?.vpnHeldReason { return reason }
    return agreeing?.heldReason
  }

  /// The address peers see when connected. The feed's own copy is the
  /// freshest; the `GET /vpn` one is used only when it agrees on the state.
  /// With no VPN set up, peers see the Mac's own address, which only
  /// `GET /vpn` knows.
  static func address(
    state: Components.Schemas.VpnState, transfer: Components.Schemas.Transfer?,
    agreeing: Components.Schemas.VpnStatus?
  ) -> String? {
    switch state {
    case .connected: nonEmpty(transfer?.vpnIp) ?? nonEmpty(agreeing?.vpnIp)
    case .none: nonEmpty(agreeing?.realIp)
    case .connecting, .down, .held: nil
    }
  }

  private static func nonEmpty(_ text: String?) -> String? {
    guard let text, !text.isEmpty else { return nil }
    return text
  }
}

/// The pill in the toolbar: a symbol, a few words, and the address when
/// the VPN is connected.
public struct VpnPill: Equatable, Sendable {
  public enum Kind: Sendable, Equatable {
    case connected, connecting, down, held, none
    /// Umbra isn't answering, or hasn't yet.
    case unknown
  }

  public let kind: Kind
  /// An SF Symbol.
  public let symbol: String
  /// "VPN down", "No VPN"...
  public let title: String
  /// The address peers see, only while the VPN is connected.
  public let address: String?
  public let role: ColorRole
  /// The tooltip and the spoken description.
  public private(set) var help: String

  init(state: Components.Schemas.VpnState, address: String?, held: HeldWords? = nil) {
    switch state {
    case .connected:
      kind = .connected
      symbol = "lock.shield.fill"
      title = "VPN"
      self.address = address
      role = .green
      help =
        address.map { "VPN connected. Peers see \($0). Click for details." }
        ?? "VPN connected. Click for details."
    case .connecting:
      kind = .connecting
      symbol = "arrow.triangle.2.circlepath"
      title = "VPN connecting…"
      self.address = nil
      role = .orange
      help = "The VPN is connecting. Nothing is sent until it is ready. Click for details."
    case .down:
      kind = .down
      symbol = "exclamationmark.shield.fill"
      title = "VPN down"
      self.address = nil
      role = .red
      help = "The VPN is down, so every torrent is stopped. Click for details."
    case .held:
      kind = .held
      let words = held ?? HeldWords(reason: nil)
      symbol = "lock.fill"
      title = words.title
      self.address = nil
      role = .red
      help = words.help
    case .none:
      kind = .none
      symbol = "shield.slash"
      title = "No VPN"
      self.address = nil
      role = .secondary
      help = "No VPN is set up, so peers see your own address. Click for details."
    }
  }

  private init(checking: Bool) {
    kind = .unknown
    symbol = "questionmark.circle"
    title = checking ? "Checking VPN…" : "VPN unknown"
    address = nil
    role = .secondary
    help =
      checking
      ? "Asking Umbra about the VPN."
      : "Umbra isn't answering, so the VPN's state isn't known right now."
  }

  static func unknown(checking: Bool) -> VpnPill { VpnPill(checking: checking) }

  /// Just after the Mac woke: Umbra is being asked afresh.
  static let afterWake: VpnPill = {
    var pill = VpnPill(checking: true)
    pill.help =
      "The Mac just woke up, so Umbra is checking the VPN. Nothing goes outside the VPN meanwhile."
    return pill
  }()
}

/// What the pill's popover lists: the state in a sentence, a few facts,
/// and which buttons to offer.
public struct VpnDetails: Equatable, Sendable {
  public struct Fact: Equatable, Sendable {
    public let label: String
    public let value: String
    /// Addresses and ports are drawn in a monospaced font.
    public let monospaced: Bool
  }

  /// "Connected via AirVPN", "VPN down"...
  public let title: String
  /// The state in a sentence; Umbra's own words where it gave some.
  public private(set) var sentence: String
  public let facts: [Fact]
  /// Umbra's re-check makes sense: connected, connecting or down (not
  /// when no VPN is set up, and not while held, as on the web page).
  public let offersCheckAgain: Bool
  /// "Open VPN Settings…": everywhere the VPN needs the person (down,
  /// held, none set up); not while it is fine or while Umbra isn't answering.
  public let offersVpnSettings: Bool
  /// "Start Without VPN…" and the question it asks first; only while held
  /// for a reason it releases (no VPN yet, or the VPN removed), never for
  /// a saved VPN that can't be used.
  public let startWithout: StartWithoutVpnConfirmation?
  /// The symbol and colour of the state, for the popover's heading.
  public let symbol: String
  public let role: ColorRole

  init(
    state: Components.Schemas.VpnState, address: String?, held: HeldWords? = nil,
    agreeing: Components.Schemas.VpnStatus?, now: Date, locale: Locale
  ) {
    let pill = VpnPill(state: state, address: address, held: held)
    symbol = pill.symbol
    role = pill.role
    var facts: [Fact] = []
    offersVpnSettings = state == .down || state == .held || state == .none
    startWithout =
      state == .held ? StartWithoutVpnConfirmation(held ?? HeldWords(reason: nil)) : nil
    switch state {
    case .connected:
      let name = agreeing?.saved.first(where: \.inUse)?.name ?? agreeing?.endpoint
      title = name.flatMap { $0.isEmpty ? nil : "Connected via \($0)" } ?? "Connected"
      sentence = "Torrents are going through the VPN, so peers see its address, not yours."
      let shown =
        address
        ?? (agreeing.flatMap { $0.ipError == nil ? nil : "Couldn't check" } ?? "Checking…")
      facts.append(Fact(label: "Address peers see", value: shown, monospaced: address != nil))
      if let port = agreeing?.forwardedPort, port > 0 {
        facts.append(Fact(label: "Forwarded port", value: String(port), monospaced: true))
      }
      offersCheckAgain = true
    case .connecting:
      title = "Connecting…"
      sentence =
        agreeing?.message.flatMap { $0.isEmpty ? nil : $0 }
        ?? "The tunnel is coming up. Nothing is sent until it is ready."
      offersCheckAgain = true
    case .down:
      title = "VPN down"
      sentence =
        agreeing?.message.flatMap { $0.isEmpty ? nil : $0 }
        ?? "The kill switch has stopped every torrent until the VPN reconnects."
      offersCheckAgain = true
    case .held:
      let words = held ?? HeldWords(reason: nil)
      // An older Umbra (no reason) keeps the heading it always had.
      title = held == HeldWords(reason: nil) || held == nil ? "VPN removed" : words.title
      sentence = words.detail
      offersCheckAgain = false
    case .none:
      title = "No VPN"
      sentence =
        "No VPN is set up, so peers see your own address. A VPN is set up in Settings."
      if let address {
        facts.append(Fact(label: "Address peers see", value: address, monospaced: true))
      }
      offersCheckAgain = false
    }
    if let since = agreeing?.since {
      facts.append(
        Fact(
          label: "Last changed", value: Self.ago(since, now: now, locale: locale),
          monospaced: false))
    }
    self.facts = facts
  }

  private init(checking: Bool) {
    title = checking ? "Checking…" : "VPN status unknown"
    sentence =
      checking
      ? "Asking Umbra about the VPN."
      : "Umbra isn't answering at the moment, so the VPN's state isn't known. "
        + "It shows again as soon as Umbra answers."
    facts = []
    offersCheckAgain = false
    offersVpnSettings = false
    startWithout = nil
    symbol = "questionmark.circle"
    role = .secondary
  }

  static func unknown(checking: Bool) -> VpnDetails { VpnDetails(checking: checking) }

  /// Just after the Mac woke: Umbra is being asked afresh.
  static let afterWake: VpnDetails = {
    var details = VpnDetails(checking: true)
    details.sentence =
      "The Mac just woke up, so Umbra is checking the VPN. Nothing goes outside the VPN meanwhile."
    return details
  }()

  /// "5 minutes ago"; "Just now" inside the first minute.
  static func ago(_ date: Date, now: Date, locale: Locale) -> String {
    if now.timeIntervalSince(date) < 60 { return "Just now" }
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = locale
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: now)
  }
}
