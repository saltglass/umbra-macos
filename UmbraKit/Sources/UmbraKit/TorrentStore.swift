import Foundation
import Observation
import UmbraAPI

/// The live torrent list, status-bar totals and VPN state, for the views to show.
///
/// It reads Umbra's live feed and keeps a `FeedState` up to date. Updates are
/// gathered for a moment (a tenth of a second) and put in together, so a burst
/// of messages makes the window redraw once, not once per message: with
/// thousands of torrents that is the difference between smooth and sluggish.
@MainActor @Observable
public final class TorrentStore {
  /// Everything the feed has said, as one value. Changing it once per batch
  /// means views are told about each batch once.
  public private(set) var feed = FeedState()

  /// Every torrent, in the order the web app keeps them.
  public var torrents: [Components.Schemas.Torrent] { feed.torrents }
  /// Whether the feed is open (or `.refused`: the credential was turned away).
  public var state: FeedConnectionState { feed.connection }
  /// False until the first list arrives.
  public var loaded: Bool { feed.loaded }
  /// Totals for the status bar (speeds, limits, free space, the VPN state...).
  public var transfer: Components.Schemas.Transfer? { feed.transfer }
  /// The VPN state, once the first totals have arrived.
  public var vpn: Components.Schemas.VpnState? { feed.transfer?.vpn }
  /// Torrents being made with "Create torrent".
  public var creations: [Components.Schemas.Creation]? { feed.creations }

  /// The feed is open and this connection's own list has arrived, so what
  /// the store holds is up to date (not left over from before a drop).
  public var isReady: Bool { feed.connection == .live && feed.loaded && !feed.awaitingSnapshot }

  /// The torrent with this hash, if it is in the list.
  public func torrent(hash: String) -> Components.Schemas.Torrent? {
    feed.torrent(hash: hash)
  }

  /// Called when a download finishes while the app is open (for a notification).
  @ObservationIgnored public var onTorrentFinished: ((Components.Schemas.TorrentFinished) -> Void)?
  /// Everyone listening for settings changes (see `listenForSettingsChanges`),
  /// by a number that is never reused.
  @ObservationIgnored private var settingsListeners: [Int: @MainActor (String) -> Void] = [:]
  @ObservationIgnored private var nextListenerID = 0

  @ObservationIgnored private let batchWindow: Duration
  @ObservationIgnored private let sleep: FeedClient.Sleep
  @ObservationIgnored private let now: @Sendable () -> Date

  @ObservationIgnored private var client: FeedClient?
  @ObservationIgnored private var readTask: Task<Void, Never>?
  @ObservationIgnored private var pending: [FeedInput] = []
  @ObservationIgnored private var refetching = false
  /// Goes up at every start and stop, so work begun for an earlier
  /// connection (a late refetch, say) can tell it no longer counts.
  @ObservationIgnored private var generation = 0
  /// The wait before the next batch is put in; nil while nothing is waiting.
  @ObservationIgnored private(set) var flushTask: Task<Void, Never>?
  /// How many times `feed` has been changed by a batch (for tests).
  @ObservationIgnored private(set) var batchCount = 0

  /// - Parameters:
  ///   - batchWindow: how long to gather updates before putting them in.
  ///   - sleep: how to wait (tests pass one that doesn't really wait).
  ///   - now: the time, for "reconnecting since".
  public init(
    batchWindow: Duration = .milliseconds(100),
    sleep: @escaping FeedClient.Sleep = { try await Task.sleep(for: $0) },
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.batchWindow = batchWindow
    self.sleep = sleep
    self.now = now
  }

  isolated deinit {
    readTask?.cancel()
    flushTask?.cancel()
  }

  /// Opens the feed to this server (closing any feed already open).
  public func start(connection: Connection) {
    start(client: FeedClient(connection: connection))
  }

  /// Opens the feed to this server, reading it from `source` (the stress
  /// feed uses this to stand in for a server).
  public func start(connection: Connection, source: any FeedByteSource) {
    start(client: FeedClient(connection: connection, source: source))
  }

  /// A store showing a fixed list and nothing else: no feed is opened.
  /// For pictures of the views and previews.
  public static func fixture(_ feed: FeedState) -> TorrentStore {
    let store = TorrentStore()
    store.feed = feed
    return store
  }

  /// Same, with a feed client of the caller's choosing (tests use one with a
  /// stand-in byte source).
  func start(client: FeedClient) {
    stop()
    self.client = client
    let generation = self.generation
    readTask = Task { [weak self] in
      do {
        for try await update in client.updates() {
          guard let self, self.generation == generation else { return }
          self.receive(update)
        }
      } catch {
        // `updates()` never ends with an error; nothing to do.
      }
    }
  }

  /// Closes the feed. The last list received stays, as on the web page.
  public func stop() {
    generation += 1
    readTask?.cancel()
    readTask = nil
    flushTask?.cancel()
    flushTask = nil
    pending = []
    refetching = false
    client = nil
    feed.connection = .connecting
  }

  /// Opens the feed again at once, its waits back at the start, keeping the
  /// list shown (after the Mac wakes: a stream from before the sleep may be
  /// dead without knowing it yet, or waiting out a long retry). Does nothing
  /// while no feed is open, or once the credential was turned away.
  public func reopen() {
    guard let client, feed.connection != .refused else { return }
    start(client: client)
  }

  /// Puts fresh rows in at once, before the next update (after an action).
  public func patch(_ rows: [Components.Schemas.Torrent]) {
    feed.patch(rows)
  }

  /// Puts the list of torrents being made in at once (after starting or removing one).
  public func setCreations(_ list: [Components.Schemas.Creation]) {
    feed.creations = list
  }

  /// Takes one update from the feed and waits for more to join it.
  func receive(_ update: FeedClient.Update) {
    switch update {
    case .opened: pending.append(.opened)
    case .event(let event): pending.append(.event(event))
    case .dropped: pending.append(.dropped(at: now()))
    case .refused: pending.append(.refused)
    }
    guard flushTask == nil else { return }
    let sleep = self.sleep
    let window = batchWindow
    flushTask = Task { [weak self] in
      do { try await sleep(window) } catch { return }
      self?.flush()
    }
  }

  /// Puts everything gathered in, as one change.
  func flush() {
    flushTask = nil
    guard !pending.isEmpty else { return }
    var next = feed
    var effects: [FeedEffect] = []
    for input in pending {
      effects += next.apply(input)
    }
    pending = []
    feed = next
    batchCount += 1

    for effect in effects {
      switch effect {
      case .refetch: refetch()
      case .finished(let finished): onTorrentFinished?(finished)
      case .settingsChanged(let group): announceSettingsChanged(group)
      }
    }
  }

  // MARK: Hearing about settings changes

  /// Calls `listener` with the group's name ("queue", "seeding"...) each
  /// time Umbra says a settings group changed: on the web page, by a
  /// schedule, or by this app. Any number of listeners can listen at once
  /// (the main window, each settings page). Listening lasts as long as the
  /// returned subscription is kept; drop it or `cancel()` it to stop.
  public func listenForSettingsChanges(
    _ listener: @escaping @MainActor (String) -> Void
  ) -> SettingsSubscription {
    nextListenerID += 1
    settingsListeners[nextListenerID] = listener
    return SettingsSubscription(store: self, id: nextListenerID)
  }

  /// Tells every listener that `group` changed (the live feed calls this;
  /// tests call it directly).
  func announceSettingsChanged(_ group: String) {
    // In the order they signed up, so behaviour never depends on a dictionary's order.
    for id in settingsListeners.keys.sorted() {
      settingsListeners[id]?(group)
    }
  }

  fileprivate func removeSettingsListener(_ id: Int) {
    settingsListeners[id] = nil
  }

  /// Fetches the whole list again after a missed update; one at a time, as
  /// the web app does. If it fails, the next reconnection's snapshot puts
  /// things right.
  private func refetch() {
    guard !refetching, let client else { return }
    refetching = true
    let generation = self.generation
    Task { [weak self] in
      let snapshot = try? await client.fetchSnapshot()
      guard let self, self.generation == generation else { return }
      self.refetching = false
      if let snapshot { self.receive(.event(.snapshot(snapshot))) }
    }
  }
}

/// A listener's place on `TorrentStore`'s list of settings listeners. When
/// it is cancelled, or nothing keeps it any more, the listener stops hearing.
@MainActor
public final class SettingsSubscription {
  private weak var store: TorrentStore?
  private let id: Int

  fileprivate init(store: TorrentStore, id: Int) {
    self.store = store
    self.id = id
  }

  public func cancel() {
    store?.removeSettingsListener(id)
    store = nil
  }

  isolated deinit { cancel() }
}
