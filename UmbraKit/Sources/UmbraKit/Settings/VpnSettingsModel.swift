import Foundation
import Observation
import UmbraAPI

/// Where the VPN page gets its connection, hears that the VPN settings
/// changed, and sees the live feed's VPN state. `AppSession` is the real
/// one; tests use a stand-in.
@MainActor
public protocol VpnSettingsSource: SettingsSource {
  /// The live feed's latest totals, which carry the VPN's state about once
  /// a second. Must be observable (an `@Observable` property).
  var liveTransfer: Components.Schemas.Transfer? { get }
  /// Whether the live feed is open (a state is only trusted while it is).
  var liveConnection: FeedConnectionState { get }
}

/// Settings → VPN, as its page shows and changes it.
///
/// The VPN isn't one of Umbra's settings groups: it has operations of its
/// own (add, edit, remove, use, order, switching, start without), so it
/// has this model instead of a `SettingsGroupModel`. The rules are the same
/// in spirit:
///
/// - **One request at a time**, in the order asked for. A request asked
///   for while another is on its way waits its turn.
/// - **Umbra decides.** After every request the VPN's state is read again,
///   so the page always shows what Umbra has. A refusal leaves `refusal`
///   holding Umbra's words, and the re-read puts back anything the page
///   had already moved (a reorder, a switch).
/// - **Read again** when Umbra says the VPN settings changed (on the web
///   page, by switching, by this app) and whenever the live feed's VPN
///   state changes (it connected, dropped, was held or released).
///
/// It never decides anything about the VPN itself: it doesn't hold or
/// release torrents, and it never starts without a VPN unless asked (the
/// page asks the person first).
///
/// **Configurations are secrets.** One goes from the sheet (or the chosen
/// file) into a single request and is dropped; this model never stores
/// one, and nothing Umbra sends back contains one.
@MainActor @Observable
public final class VpnSettingsModel: SettingsGroupStatus,
  @MainActor CustomReflectable
{
  public typealias Status = Components.Schemas.VpnStatus
  public typealias Saved = Components.Schemas.VpnProfile

  public private(set) var phase: SettingsPhase
  /// What Umbra last said about the VPN (`GET /vpn`), with the page's
  /// on-their-way changes (a new order, switching) applied. Nil until loaded.
  public private(set) var status: Status?
  /// Umbra's explanation of the last request it refused; nil once a later
  /// one succeeds. (The paste and edit sheets get theirs directly instead.)
  public private(set) var refusal: UmbraError?
  /// True while a request is on its way.
  public private(set) var isSending = false
  /// True while "Check Again" waits for Umbra.
  public private(set) var isChecking = false

  /// For pictures: the feed's totals and state, fixed.
  @ObservationIgnored private let fixedTransfer: Components.Schemas.Transfer?
  /// For pictures: the clock "Last changed" is counted from.
  @ObservationIgnored private var fixedNow: Date?
  @ObservationIgnored private let isFixture: Bool

  @ObservationIgnored private var actions: SettingsActions?
  @ObservationIgnored private weak var source: (any VpnSettingsSource)?
  @ObservationIgnored private var subscription: SettingsSubscription?
  /// Goes up with every new connection, so an answer from an old one is ignored.
  @ObservationIgnored private var generation = 0
  /// The request on its way, if any; the next one waits for it.
  @ObservationIgnored private var tail: Task<Void, Never>?
  @ObservationIgnored private var pending = 0
  /// The feed's VPN state and reason last time it was looked at.
  @ObservationIgnored private var lastFeedKey: String?

  /// A model following `source`.
  public init(source: any VpnSettingsSource) {
    self.source = source
    fixedTransfer = nil
    fixedNow = nil
    isFixture = false
    phase = .notConnected
    subscription = source.listenForSettingsChanges { [weak self] group in
      guard group == "vpn" else { return }
      self?.reload()
    }
    connect(source.settingsActions)
    followConnection()
    followFeed()
  }

  /// A model showing a fixed state and nothing else; it never connects or
  /// sends (for pictures of the page and previews).
  public init(
    fixture status: Status?, transfer: Components.Schemas.Transfer? = nil,
    phase: SettingsPhase = .loaded, refusal: UmbraError? = nil, now: Date? = nil
  ) {
    fixedNow = now
    self.status = status
    self.phase = phase
    self.refusal = refusal
    fixedTransfer = transfer
    isFixture = true
  }

  // MARK: What the page shows

  /// The state, address, forwarded port and "last changed", worked out
  /// exactly as for the toolbar pill's popover.
  public func summary(now: Date? = nil, locale: Locale = .current) -> VpnSummary {
    VpnSummary(
      transfer: transfer, status: status,
      connection: isFixture ? .live : source?.liveConnection ?? .connecting,
      now: now ?? fixedNow ?? Date(), locale: locale)
  }

  /// The live feed's latest totals (fixed ones in pictures).
  private var transfer: Components.Schemas.Transfer? {
    isFixture ? fixedTransfer : source?.liveTransfer
  }

  /// The saved VPNs, in the order switching tries them.
  public var saved: [Saved] { status?.saved ?? [] }

  /// The one switching (or removing the one in use) would go to next: the
  /// one after the VPN in use, going round. Nil with fewer than two.
  public var nextInLine: Saved? {
    let list = saved
    guard list.count > 1, let at = list.firstIndex(where: \.inUse) else { return nil }
    return list[(at + 1) % list.count]
  }

  /// What is true when no VPN is in the way of the torrents: nil while one
  /// is saved (its state shows at the top instead).
  public enum NoVpnSituation: Equatable, Sendable {
    /// Held: none set up yet, or the last one removed (`words` say which).
    case held(HeldWords)
    /// Running on this Mac's own connection, because the person chose to.
    case runningWithout

    /// What the page says about it.
    public var text: String {
      switch self {
      case .held(let words) where words == HeldWords(reason: .noVpnYet):
        "Torrents are held because no VPN is set up yet: nothing has gone out to the network. "
          + "Add a VPN above, or start without one."
      case .held(let words) where words == HeldWords(reason: .vpnUnusable):
        "Torrents are held because the saved VPN can't be used. Fix or replace it above."
      case .held:
        "Torrents are held because the VPN was removed, so your real IP address is never "
          + "exposed. Add a VPN above, or start without one."
      case .runningWithout:
        "No VPN is set up and you chose to run without one, so peers see this Mac's real IP "
          + "address. Add a VPN above to put torrents behind it again."
      }
    }
  }

  public var noVpnSituation: NoVpnSituation? {
    guard let status, !status.configured else { return nil }
    let summary = summary()
    switch summary.pill.kind {
    case .held:
      let agreeing = status.state == .held ? status : nil
      return .held(HeldWords(reason: VpnSummary.heldReason(transfer, agreeing)))
    case .none: return .runningWithout
    default: return nil
    }
  }

  /// The question "Start Without VPN…" asks; nil where it isn't offered
  /// (not held, or held for a reason it can't release).
  public var startWithout: StartWithoutVpnConfirmation? {
    summary().details.startWithout
  }

  /// What "Remove…" asks, which says what will happen (the web page's words).
  public struct RemoveQuestion: Equatable, Sendable {
    public let title: String
    public let message: String
    public let button: String
  }

  public func removeQuestion(for id: String) -> RemoveQuestion? {
    let list = saved
    guard let at = list.firstIndex(where: { $0.id == id }) else { return nil }
    let vpn = list[at]
    if list.count == 1 {
      return RemoveQuestion(
        title: "Remove the VPN?",
        message:
          "Every torrent stops and stays held, so your real address is never shown by surprise. "
          + "Afterwards, add another VPN, or choose “Start Without VPN” to run torrents on "
          + "your own connection.",
        button: "Remove VPN")
    }
    let next = list[(at + 1) % list.count]
    return RemoveQuestion(
      title: "Remove “\(vpn.name)”?",
      message: vpn.inUse
        ? "It's in use: torrents switch to “\(next.name)”."
        : "It isn't in use, so nothing stops.",
      button: "Remove")
  }

  // MARK: Asking Umbra

  /// "Check Again": Umbra looks at the VPN and the addresses now.
  public func checkAgain() {
    guard actions != nil, !isChecking else { return }
    isChecking = true
    Task {
      // The read-back that follows every request picks up what it found.
      _ = await run(reportRefusal: true) { actions async throws(UmbraError) in
        _ = try await actions.vpn(refresh: true)
      }
      isChecking = false
    }
  }

  /// Puts a saved VPN in use.
  public func use(_ id: String) {
    send { actions async throws(UmbraError) in try await actions.useVpn(id: id) }
  }

  /// Removes a saved VPN (the page has asked first).
  public func remove(_ id: String) {
    send { actions async throws(UmbraError) in try await actions.removeVpn(id: id) }
  }

  /// Reorders the saved VPNs (a drag in the list). Shown at once; put back
  /// if Umbra refuses.
  public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
    let ids = saved.map(\.id)
    let moving = source.map { ids[$0] }
    var rest = ids.enumerated().filter { !source.contains($0.offset) }.map(\.element)
    // The drop point, counted among the ones that stay.
    let at = destination - source.filter { $0 < destination }.count
    rest.insert(contentsOf: moving, at: min(max(at, 0), rest.count))
    reorder(rest)
  }

  /// Moves one saved VPN up (-1) or down (+1) the list.
  public func move(_ id: String, by step: Int) {
    var ids = saved.map(\.id)
    guard let at = ids.firstIndex(of: id), ids.indices.contains(at + step) else { return }
    ids.swapAt(at, at + step)
    reorder(ids)
  }

  /// Whether `move(id, by:)` can go that way.
  public func canMove(_ id: String, by step: Int) -> Bool {
    guard let at = saved.firstIndex(where: { $0.id == id }) else { return false }
    return saved.indices.contains(at + step)
  }

  private func reorder(_ ids: [String]) {
    guard var shown = status, ids != saved.map(\.id) else { return }
    shown.saved = ids.compactMap { id in shown.saved.first { $0.id == id } }
    status = shown
    send { actions async throws(UmbraError) in try await actions.orderVpns(ids) }
  }

  /// Turns switching to the next saved VPN on or off.
  public func setFailover(enabled: Bool) {
    guard let minutes = status?.failover.minutes else { return }
    setFailover(enabled: enabled, minutes: minutes)
  }

  /// How long the VPN in use is down before switching.
  public func setFailover(minutes: Int) {
    guard let enabled = status?.failover.enabled, minutes != status?.failover.minutes else {
      return
    }
    setFailover(enabled: enabled, minutes: minutes)
  }

  private func setFailover(enabled: Bool, minutes: Int) {
    status?.failover = .init(enabled: enabled, minutes: minutes)
    send { actions async throws(UmbraError) in
      try await actions.setVpnFailover(enabled: enabled, minutes: minutes)
    }
  }

  /// The forwarded port of the VPN in use (0 is none), set from the page
  /// itself as on the web page. Its name and file stay as they are.
  public func setForwardedPort(_ port: Int) {
    guard let inUse = saved.first(where: \.inUse), port != (inUse.forwardedPort ?? 0) else {
      return
    }
    let id = inUse.id
    send { actions async throws(UmbraError) in
      try await actions.editVpn(id: id, forwardedPort: port)
    }
  }

  /// Asks Umbra to run without a VPN. Only ever called once the person
  /// has confirmed it in the alert.
  public func startWithoutVpn() {
    send { actions async throws(UmbraError) in try await actions.startWithoutVpn() }
  }

  /// Saves a pasted configuration and waits for Umbra. Returns its refusal
  /// (the sheet stays open and shows it), or nil when saved (the sheet
  /// clears its text and closes). The configuration isn't kept here.
  public func add(_ draft: VpnPasteDraft) async -> UmbraError? {
    let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let configuration = draft.configuration
    return await run(reportRefusal: false) { actions async throws(UmbraError) in
      _ = try await actions.addVpn(configuration, name: name.isEmpty ? nil : name)
    }
  }

  /// Saves the configuration in a file the person has just chosen. It is
  /// read only now, sent, and dropped. A refusal shows on the page.
  public func add(fileAt url: URL) async {
    let configuration: VpnConfiguration
    do {
      configuration = try Self.readConfiguration(at: url)
    } catch {
      refusal = UmbraError(
        code: "unreadable", message: "Couldn't read “\(url.lastPathComponent)”.")
      return
    }
    _ = await run(reportRefusal: true) { actions async throws(UmbraError) in
      _ = try await actions.addVpn(configuration)
    }
  }

  /// Renames a saved VPN, sets its forwarded port, or replaces its file;
  /// waits for Umbra and returns its refusal (the sheet stays open), or nil.
  public func edit(
    _ id: String, name: String, forwardedPort: Int, configuration: VpnConfiguration?
  ) async -> UmbraError? {
    await run(reportRefusal: false) { actions async throws(UmbraError) in
      try await actions.editVpn(
        id: id, name: name, forwardedPort: forwardedPort, configuration: configuration)
    }
  }

  /// Reads a chosen .conf file (asking for access first where macOS wants it).
  public static func readConfiguration(at url: URL) throws -> VpnConfiguration {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    return VpnConfiguration(try String(contentsOf: url, encoding: .utf8))
  }

  /// Umbra's words for a refusal. When it names the fields at fault (the
  /// configuration, the name), those say more than its general line.
  public static func explanation(for error: UmbraError) -> String {
    let named = error.fields.sorted { $0.key < $1.key }.map(\.value)
    return named.isEmpty ? error.message : named.joined(separator: " ")
  }

  /// Printing or `dump`ing the model shows what the page shows and
  /// nothing of the connection behind it (its launch token, or a request
  /// on its way that holds a configuration).
  public var customMirror: Mirror {
    Mirror(
      self,
      children: [
        "phase": phase as Any, "status": status as Any, "refusal": refusal as Any,
        "isSending": isSending,
      ])
  }

  /// Tries reading again after `loadFailed`.
  public func retry() {
    guard actions != nil else { return }
    if status == nil { phase = .loading }
    reload()
  }

  // MARK: One request at a time

  /// Sends a request with no answer to wait for; a refusal goes to `refusal`.
  private func send(_ work: @escaping @Sendable (SettingsActions) async throws(UmbraError) -> Void)
  {
    guard actions != nil else { return }
    // Counted as on its way from now, not from when the task gets going.
    let generation = self.generation
    pending += 1
    isSending = true
    Task {
      _ = await run(reportRefusal: true, work)
      guard generation == self.generation else { return }
      pending -= 1
      isSending = pending > 0
    }
  }

  /// Runs `work` after every request before it, then reads the VPN's state
  /// again (so the page shows what Umbra has, whether it agreed or not).
  /// Returns Umbra's refusal, or nil.
  private func run(
    reportRefusal: Bool,
    _ work: @escaping @Sendable (SettingsActions) async throws(UmbraError) -> Void
  ) async -> UmbraError? {
    guard let actions else {
      return UmbraError(code: "not_connected", message: "Umbra isn't running.")
    }
    let generation = self.generation
    let previous = tail
    pending += 1
    isSending = true
    let job = Task { @MainActor () -> (UmbraError?, Status?) in
      await previous?.value
      var failure: UmbraError?
      do throws(UmbraError) { try await work(actions) } catch { failure = error }
      // Read back what Umbra has now, refused or not.
      let fresh = try? await actions.vpn()
      return (failure, fresh)
    }
    tail = Task { _ = await job.value }
    let (failure, fresh) = await job.value
    guard generation == self.generation else { return failure }
    pending -= 1
    isSending = pending > 0
    if let fresh { status = fresh }
    if reportRefusal { refusal = failure }
    return failure
  }

  /// Reads the VPN's state again (after the requests already asked for).
  private func reload() {
    guard let actions else { return }
    let generation = self.generation
    let previous = tail
    let job = Task { @MainActor () -> Result<Status, UmbraError> in
      await previous?.value
      do throws(UmbraError) { return .success(try await actions.vpn()) } catch {
        return .failure(error)
      }
    }
    tail = Task { _ = await job.value }
    Task {
      let result = await job.value
      guard generation == self.generation else { return }
      switch result {
      case .success(let fresh):
        // Leave a page change on its way alone: its own read-back follows.
        if pending == 0 { status = fresh }
        phase = .loaded
      case .failure(let error):
        if status == nil { phase = .loadFailed(message: error.message) }
      }
    }
  }

  // MARK: Following the connection and the feed

  private func connect(_ actions: SettingsActions?) {
    generation += 1
    self.actions = actions
    tail = nil
    pending = 0
    isSending = false
    isChecking = false
    status = nil
    refusal = nil
    guard actions != nil else {
      phase = .notConnected
      return
    }
    phase = .loading
    reload()
  }

  private func followConnection() {
    withObservationTracking {
      _ = source?.settingsActions
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.connect(self.source?.settingsActions)
        self.followConnection()
      }
    }
  }

  /// The feed sends its totals every second; only a change in the VPN's
  /// state or held reason means a read.
  private func followFeed() {
    let key = withObservationTracking {
      Self.feedKey(source?.liveTransfer)
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in self?.followFeed() }
    }
    if let last = lastFeedKey, last != key { reload() }
    lastFeedKey = key
  }

  static func feedKey(_ transfer: Components.Schemas.Transfer?) -> String {
    guard let transfer else { return "" }
    return "\(transfer.vpn.rawValue) \(transfer.vpnHeldReason?.rawValue ?? "")"
  }
}

/// What the "Paste Configuration…" sheet holds while it is open: a name
/// and the pasted text. The text is a secret, so the draft never shows it
/// in `description` or a `dump`, and the sheet empties it as soon as Umbra
/// has saved it. It is never written anywhere.
public struct VpnPasteDraft: Equatable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible, CustomReflectable
{
  public var name = ""
  /// The pasted text, as the text area edits it.
  public var text: String {
    get { configuration.text }
    set { configuration = VpnConfiguration(newValue) }
  }
  public private(set) var configuration = VpnConfiguration("")

  public init(name: String = "") {
    self.name = name
  }

  /// Nothing to send yet.
  public var isBlank: Bool { configuration.isBlank }

  /// Empties it (after saving, or when the sheet closes).
  public mutating func clear() {
    self = VpnPasteDraft()
  }

  public var description: String {
    "VpnPasteDraft(name: \(name), configuration: \(configuration))"
  }
  public var debugDescription: String { description }
  public var customMirror: Mirror {
    Mirror(self, children: ["name": name, "configuration": configuration])
  }
}
