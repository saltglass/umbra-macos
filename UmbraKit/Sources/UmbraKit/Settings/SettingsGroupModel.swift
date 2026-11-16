import Foundation
import Observation

/// Where settings models get their connection to Umbra and hear that a
/// group changed. `AppSession` is the real one; tests use a stand-in.
@MainActor
public protocol SettingsSource: AnyObject {
  /// For reading and replacing settings; nil while not connected. It must
  /// be observable (an `@Observable` property), so models notice a new
  /// connection and read their group again.
  var settingsActions: SettingsActions? { get }
  /// See `TorrentStore.listenForSettingsChanges`.
  func listenForSettingsChanges(
    _ listener: @escaping @MainActor (String) -> Void
  ) -> SettingsSubscription
}

/// Whether a settings group has anything to show.
public enum SettingsPhase: Equatable, Sendable {
  /// Umbra isn't running or the app isn't connected to it.
  case notConnected
  /// Reading the group for the first time on this connection.
  case loading
  /// Reading the group failed; `message` says why. `retry()` tries again.
  case loadFailed(message: String)
  /// The model's `value` holds the group.
  case loaded

  /// One state for a page showing several groups: the page can show its
  /// settings only when every group is loaded; otherwise it shows the
  /// first of these that applies: not connected, failed, loading.
  public static func combined(_ phases: [SettingsPhase]) -> SettingsPhase {
    if phases.contains(.notConnected) { return .notConnected }
    for case .loadFailed(let message) in phases { return .loadFailed(message: message) }
    if phases.contains(.loading) { return .loading }
    return .loaded
  }
}

/// What a page needs to know about any group, whatever its settings.
@MainActor
public protocol SettingsGroupStatus: AnyObject {
  var phase: SettingsPhase { get }
  func retry()
}

/// One settings group as a settings page shows and changes it.
///
/// The rules (Dan, 2026-11-13): changes apply as they're made; there is no
/// Save button.
///
/// - A switch or a menu calls `set` and the change is sent at once.
/// - A typed field calls `type` as the person types (nothing is sent) and
///   `commit` on Return or on leaving the field; only then is it sent.
/// - Sending reads-modifies-writes the whole group: the change is applied
///   to the latest value Umbra gave, and the whole group is sent.
/// - One request at a time per group. Changes made while one is on its way
///   wait, and all that waited go together in the next request, in the
///   order they were made, so the newest always wins and none is lost.
/// - If Umbra refuses, the page goes back to what Umbra has stored and
///   `refusal` holds Umbra's explanation, to show on the page.
/// - When Umbra says the group changed (on the web page, by a schedule, or
///   by this app), it is read again. Text being typed in a field stays as
///   it is; it is applied to the new value when committed.
///
/// Nothing is checked here beyond "is this a number at all": Umbra decides
/// what is allowed, and says why not.
@MainActor @Observable
public final class SettingsGroupModel<Value: Equatable & Sendable>: SettingsGroupStatus {
  public typealias Phase = SettingsPhase

  public private(set) var phase: Phase
  /// What the page shows: the group as Umbra last gave it, with the
  /// person's changes that are on their way (or waiting) applied on top.
  /// Nil until loaded.
  public private(set) var value: Value?
  /// Umbra's explanation of the last change it refused; nil once a later
  /// change is saved. Its `fields` name the fields at fault.
  public private(set) var refusal: UmbraError?
  /// True while a change is on its way to Umbra.
  public private(set) var isSending = false
  /// Text typed into fields and not yet committed, by field.
  private var drafts: [AnyKeyPath: String] = [:]

  public let group: SettingsGroup<Value>

  /// A change to the group, as the person made it.
  typealias Change = (inout Value) -> Void

  /// The group exactly as Umbra last gave it.
  @ObservationIgnored private var stored: Value?
  /// Changes in the request on its way, and changes waiting for the next one.
  @ObservationIgnored private var sending: [Change] = []
  @ObservationIgnored private var waiting: [Change] = []
  /// The group needs reading (first load, a new connection, or Umbra said
  /// it changed).
  @ObservationIgnored private var readWanted = false
  /// A request (read or write) is on its way; the next waits for it.
  @ObservationIgnored private var busy = false
  /// Goes up with every new connection, so an answer that arrives from an
  /// old one is ignored.
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var actions: SettingsActions?
  @ObservationIgnored private weak var source: (any SettingsSource)?
  @ObservationIgnored private var subscription: SettingsSubscription?

  /// A model that follows `source`: it reads the group whenever a
  /// connection appears, and again whenever Umbra says the group changed.
  public init(_ group: SettingsGroup<Value>, source: any SettingsSource) {
    self.group = group
    self.source = source
    phase = .notConnected
    let name = group.name
    subscription = source.listenForSettingsChanges { [weak self] changed in
      guard changed == name else { return }
      self?.groupChanged()
    }
    connect(source.settingsActions)
    followConnection()
  }

  /// A model showing a fixed value and nothing else; it never connects or
  /// sends (for pictures of the pages and previews).
  public init(
    _ group: SettingsGroup<Value>, fixture value: Value?, phase: Phase = .loaded,
    refusal: UmbraError? = nil
  ) {
    self.group = group
    self.phase = phase
    self.stored = value
    self.value = value
    self.refusal = refusal
  }

  // MARK: Changing

  /// Sets one setting and sends it now (a switch, a menu).
  public func set<T>(_ field: WritableKeyPath<Value, T>, to newValue: T) {
    change { $0[keyPath: field] = newValue }
  }

  /// Any change to the group, sent now (for edits that touch several
  /// settings at once, such as adding a category). Does nothing until
  /// the group is loaded.
  public func change(_ edit: @escaping (inout Value) -> Void) {
    guard phase == .loaded, stored != nil, actions != nil else { return }
    waiting.append(edit)
    updateValue()
    sendNext()
  }

  // MARK: Typed fields

  /// The text a typed field shows: what the person is typing, if anything,
  /// else the setting as `format` writes it.
  public func text<T>(_ field: KeyPath<Value, T>, as format: SettingsFormat<T>) -> String {
    if let draft = drafts[field] { return draft }
    guard let value else { return "" }
    return format.text(value[keyPath: field])
  }

  /// The person typed into a field. Nothing is sent until `commit`.
  public func type<T>(_ text: String, into field: KeyPath<Value, T>) {
    guard phase == .loaded else { return }
    drafts[field] = text
  }

  /// Whether the person has typed into this field since it was last committed.
  public func isTyping<T>(in field: KeyPath<Value, T>) -> Bool {
    drafts[field] != nil
  }

  /// Return was pressed in a field, or the person left it: send what they
  /// typed, if it reads as a value and differs from what's there. Text
  /// that can't be read is dropped and the field shows the setting again.
  public func commit<T: Equatable>(
    _ field: WritableKeyPath<Value, T>, as format: SettingsFormat<T>
  ) {
    guard let draft = drafts.removeValue(forKey: field), let value else { return }
    guard case .value(let typed) = format.read(draft), typed != value[keyPath: field] else {
      return
    }
    set(field, to: typed)
  }

  // MARK: Umbra's refusals

  /// Umbra's explanation for one field ("maxActiveDownloads"), if its
  /// last refusal named it.
  public func problem(for field: String) -> String? {
    refusal?.fields[field]
  }

  /// Umbra's explanation for the page as a whole: set when the last
  /// refusal named no field (when it names fields, they say it all).
  public var pageProblem: String? {
    guard let refusal, refusal.fields.isEmpty else { return nil }
    return refusal.message
  }

  /// Tries reading the group again after `loadFailed`.
  public func retry() {
    guard actions != nil else { return }
    readWanted = true
    if stored == nil { phase = .loading }
    sendNext()
  }

  // MARK: Following the connection

  /// Watches the source's connection; observation tells once per change,
  /// so this signs up again each time.
  private func followConnection() {
    withObservationTracking {
      _ = source?.settingsActions
    } onChange: { [weak self] in
      // Told just before the change; act just after it, on the main actor.
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.connect(self.source?.settingsActions)
        self.followConnection()
      }
    }
  }

  /// A new connection (or none): start again from nothing. Changes not
  /// yet confirmed can't be sent any more, so they are dropped.
  func connect(_ actions: SettingsActions?) {
    generation += 1
    self.actions = actions
    busy = false
    isSending = false
    sending = []
    waiting = []
    drafts = [:]
    stored = nil
    value = nil
    refusal = nil
    guard actions != nil else {
      phase = .notConnected
      return
    }
    phase = .loading
    readWanted = true
    sendNext()
  }

  /// Umbra said the group changed: read it again when nothing else is on
  /// its way.
  private func groupChanged() {
    guard actions != nil else { return }
    readWanted = true
    sendNext()
  }

  // MARK: Talking to Umbra, one request at a time

  /// Starts the next request, if one is due and none is on its way. A
  /// read comes first, so changes apply to the freshest value.
  private func sendNext() {
    guard !busy, let actions else { return }
    let generation = self.generation
    let group = self.group
    if readWanted {
      readWanted = false
      busy = true
      Task { [weak self] in
        let result: Result<Value, UmbraError>
        do throws(UmbraError) {
          result = .success(try await group.read(actions))
        } catch { result = .failure(error) }
        guard let self, self.generation == generation else { return }
        self.busy = false
        self.finishRead(result)
        self.sendNext()
      }
      return
    }
    guard !waiting.isEmpty, var body = stored else { return }
    sending = waiting
    waiting = []
    for edit in sending { edit(&body) }
    // Nothing differs from what Umbra has (switched on then off again): no request.
    if body == stored {
      sending = []
      updateValue()
      return
    }
    busy = true
    isSending = true
    Task { [weak self] in
      let result: Result<Value, UmbraError>
      do throws(UmbraError) {
        result = .success(try await group.write(body, actions))
      } catch {
        result = .failure(error)
      }
      guard let self, self.generation == generation else { return }
      self.busy = false
      self.isSending = false
      self.finishWrite(result)
      self.sendNext()
    }
  }

  private func finishRead(_ result: Result<Value, UmbraError>) {
    switch result {
    case .success(let fresh):
      stored = fresh
      phase = .loaded
      updateValue()
    case .failure(let error):
      // With a value already showing, keep it: the next change notice or
      // connection reads again. Without one, say why there's nothing.
      if stored == nil { phase = .loadFailed(message: error.message) }
    }
  }

  private func finishWrite(_ result: Result<Value, UmbraError>) {
    switch result {
    case .success(let saved):
      stored = saved
      refusal = nil
    case .failure(let error):
      // The refused changes are dropped, so the page shows what Umbra has.
      refusal = error
    }
    sending = []
    updateValue()
  }

  /// Remakes `value` from what Umbra has plus the changes not yet confirmed.
  private func updateValue() {
    guard var shown = stored else {
      if value != nil { value = nil }
      return
    }
    for edit in sending + waiting { edit(&shown) }
    if shown != value { value = shown }
  }
}

/// Keeps one model per settings group for the whole app, so every page
/// (and every opening of the Settings window) shares it and it stays
/// current. Pages ask for their group's model with `model(for:)`.
@MainActor
public final class SettingsModels {
  private let source: any SettingsSource
  private var models: [String: AnyObject] = [:]

  public init(source: any SettingsSource) {
    self.source = source
  }

  /// Settings → VPN's model, made the first time it is asked for. Nil
  /// when the source can't show the live feed's VPN state (never for the app).
  public var vpn: VpnSettingsModel? {
    if let vpnModel { return vpnModel }
    guard let source = source as? any VpnSettingsSource else { return nil }
    let model = VpnSettingsModel(source: source)
    vpnModel = model
    return model
  }
  private var vpnModel: VpnSettingsModel?

  /// The model for `group`, made the first time it is asked for.
  public func model<Value>(for group: SettingsGroup<Value>) -> SettingsGroupModel<Value> {
    if let model = models[group.name] as? SettingsGroupModel<Value> { return model }
    let model = SettingsGroupModel(group, source: source)
    models[group.name] = model
    return model
  }
}
