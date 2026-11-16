import Foundation
import Observation
import UmbraAPI

/// Ties the app together: the helper (or a development server), the live
/// torrent list, and the VPN line, for the window to show.
///
/// When the helper restarts it comes back with a new launch token, so the
/// torrent list is reconnected with the new `Connection` each time.
@MainActor @Observable
public final class AppSession {
  /// What the window shows above (or instead of) the list.
  public enum Phase: Sendable, Equatable {
    case starting
    case running
    /// The helper stopped and is being started again.
    case reconnecting(attempt: Int)
    /// Quitting: waiting while the engine saves.
    case saving
    case stopped
    case failed(message: String, logTail: [String])
  }

  public private(set) var phase: Phase = .starting
  /// The live torrent list.
  public let store: TorrentStore
  /// The VPN's state and the addresses the world sees (GET /vpn), refreshed
  /// every 30 seconds.
  public private(set) var vpnStatus: Components.Schemas.VpnStatus?
  /// The port Umbra listens on for peers (Settings → Connection), asked for
  /// every few minutes; nil until known.
  public private(set) var listenPort: Int?
  /// The Umbra server's own version ("Version and uptime"), asked for once
  /// per connection (the About window shows it); nil until it has answered
  /// and while not connected.
  public private(set) var serverVersion: String?
  /// For changing torrents (pause, resume...); nil while not connected.
  public private(set) var actions: TorrentActions?
  /// For the Create Torrent sheet; nil while not connected.
  public private(set) var creationActions: CreateTorrentActions?
  /// For reading and changing Umbra's settings; nil while not connected.
  /// Settings pages follow it (see `SettingsGroupModel`): a new value
  /// means a new connection, so they read their settings again.
  public private(set) var settingsActions: SettingsActions?
  // --- Logs window: where Umbra is, for reading its log ---
  /// The connection to Umbra while there is a real one (not the stress
  /// feed, not a fixture); nil otherwise. The Logs window follows it.
  public private(set) var connection: Connection?
  // --- end of the Logs window's block ---
  /// True when connected to a development server instead of the helper.
  public var isAttached: Bool { attached != nil }
  /// True from the Mac going to sleep until Umbra has answered afresh after
  /// it woke (see `WakeRecovery`): the VPN then reads "Checking VPN…".
  public private(set) var isCheckingVpnAfterWake = false

  /// The address peers see: the VPN's when there is one, else the Mac's own.
  /// Nil until Umbra has looked it up (with loopback-only development
  /// helpers it never does).
  public var peerAddress: String? {
    guard let vpnStatus else { return nil }
    if vpnStatus.state != .none { return vpnStatus.vpnIp }
    return vpnStatus.realIp
  }

  @ObservationIgnored private let supervisor: HelperSupervisor?
  @ObservationIgnored private let attached: Connection?
  @ObservationIgnored private var watchTask: Task<Void, Never>?
  @ObservationIgnored private var vpnTask: Task<Void, Never>?
  @ObservationIgnored private var settingsTask: Task<Void, Never>?
  @ObservationIgnored private var versionTask: Task<Void, Never>?
  /// Where the live feed is read from instead of the server, if anywhere
  /// (the development stress feed).
  @ObservationIgnored private let feedSource: (any FeedByteSource)?
  /// True for a session that only shows a fixed list (pictures, previews).
  @ObservationIgnored private let isFixture: Bool
  /// What to do around a sleep, and the loop that drives it while it matters.
  @ObservationIgnored private var wake = WakeRecovery()
  @ObservationIgnored private var wakeTask: Task<Void, Never>?
  /// True while a backup is being restored: the window keeps showing
  /// "Starting…" while the helper stops, restores and starts again.
  @ObservationIgnored private var isRestoring = false

  /// Runs the bundled helper with this supervisor.
  public init(supervisor: HelperSupervisor, store: TorrentStore = TorrentStore()) {
    self.supervisor = supervisor
    self.attached = nil
    self.store = store
    self.feedSource = nil
    self.isFixture = false
  }

  /// Connects to a server that is already running (development only).
  /// With `feedSource`, the live feed is read from it instead (the stress
  /// feed), and the VPN isn't asked about: there is no server to ask.
  public init(
    attachingTo connection: Connection, feedSource: (any FeedByteSource)? = nil,
    store: TorrentStore = TorrentStore()
  ) {
    self.supervisor = nil
    self.attached = connection
    self.store = store
    self.feedSource = feedSource
    self.isFixture = false
  }

  /// A session that only shows `store` in the given phase, starting
  /// nothing (for pictures of the views).
  public init(
    fixture store: TorrentStore, phase: Phase = .running, listenPort: Int? = nil,
    serverVersion: String? = nil
  ) {
    self.supervisor = nil
    self.attached = nil
    self.store = store
    self.feedSource = nil
    self.isFixture = true
    self.phase = phase
    self.listenPort = listenPort
    self.serverVersion = serverVersion
  }

  /// Starts the helper (or connects to the development server).
  public func start() {
    if isFixture { return }
    if let attached {
      phase = .running
      connect(attached)
      return
    }
    guard let supervisor, watchTask == nil else { return }
    watchTask = Task { [weak self] in
      for await state in await supervisor.states() {
        guard let self else { return }
        self.follow(state)
      }
    }
    Task {
      // A failure is reported through the states, which the window shows.
      try? await supervisor.start()
    }
  }

  /// Asks Umbra to check the VPN again now (the "Check Again" buttons) and
  /// keeps the answer, without waiting for the next 30-second look.
  /// Does nothing while not connected.
  public func checkVpnAgain() async throws(UmbraError) {
    guard let actions else { return }
    let status = try await actions.checkVpnAgain()
    // The connection may have been replaced while waiting; an answer from
    // the old one would be out of date.
    guard self.actions != nil else { return }
    vpnStatus = status
  }

  /// Asks Umbra to run without a VPN (the pill's and the banner's "Start
  /// Without VPN…", once the person has confirmed it), then reads the VPN's
  /// state again so the pill catches up. Does nothing while not connected.
  public func startWithoutVpn() async throws(UmbraError) {
    guard let settingsActions else { return }
    try await settingsActions.startWithoutVpn()
    let status = try await settingsActions.vpn()
    guard self.settingsActions != nil else { return }
    vpnStatus = status
  }

  // MARK: Sleep and wake

  /// The Mac is about to sleep (`NSWorkspace.willSleepNotification`).
  public func macWillSleep() {
    if isFixture { return }
    wake.willSleep(at: .now, connected: actions != nil)
    followWake([])
  }

  /// The Mac woke up (`NSWorkspace.didWakeNotification`): the live feed is
  /// opened afresh and Umbra is asked about the VPN at once, then again
  /// every few seconds until it has settled.
  public func macDidWake() {
    if isFixture { return }
    followWake(wake.didWake(at: .now, connected: actions != nil))
  }

  /// Carries out `WakeRecovery`'s steps, and keeps its clock ticking while
  /// it is checking (or asleep, in case the wake notice never comes).
  private func followWake(_ steps: [WakeRecovery.Step]) {
    isCheckingVpnAfterWake = wake.isChecking
    for step in steps {
      switch step {
      case .reopenFeed:
        store.reopen()
      case .checkVpn(let round):
        Task { [weak self] in
          var state: Components.Schemas.VpnState?
          do {
            try await self?.checkVpnAgain()
            state = self?.vpnStatus?.state
          } catch {
            state = nil  // asked again in a few seconds
          }
          guard let self else { return }
          self.wake.answered(state, round: round, feedLive: self.store.state == .live, at: .now)
          self.followWake([])
        }
      }
    }
    guard wake.isChecking || wake.isAsleep else {
      wakeTask?.cancel()
      wakeTask = nil
      return
    }
    guard wakeTask == nil else { return }
    wakeTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(500))
        guard let self, !Task.isCancelled else { return }
        let steps = self.wake.tick(
          at: .now, connected: self.actions != nil, feedLive: self.store.state == .live)
        if !self.wake.isChecking && !self.wake.isAsleep {
          self.wakeTask = nil
          self.isCheckingVpnAfterWake = false
          return
        }
        self.followWake(steps)
      }
    }
  }

  private func follow(_ state: HelperState) {
    switch state {
    case .stopped:
      // The first state is `.stopped`, before anything has started.
      if phase != .starting, !isRestoring { phase = .stopped }
    case .starting:
      phase = .starting
    case .running(let connection):
      phase = .running
      connect(connection)
    case .restarting(let attempt):
      disconnect()
      phase = .reconnecting(attempt: attempt)
    case .stopping:
      disconnect()
      if !isRestoring { phase = .saving }
    case .failed(let message, let logTail):
      disconnect()
      phase = .failed(message: message, logTail: logTail)
    }
  }

  private func connect(_ connection: Connection) {
    vpnTask?.cancel()
    settingsTask?.cancel()
    versionTask?.cancel()
    actions = TorrentActions(connection: connection)
    creationActions = CreateTorrentActions(connection: connection)
    if let feedSource {
      store.start(connection: connection, source: feedSource)
      return
    }
    store.start(connection: connection)
    settingsActions = SettingsActions(connection: connection)
    self.connection = connection  // for the Logs window
    let client = connection.makeClient()
    vpnTask = Task { [weak self] in
      while !Task.isCancelled {
        let status = try? await client.getVpn().ok.body.json
        guard let self, !Task.isCancelled else { return }
        if let status { self.vpnStatus = status }
        try? await Task.sleep(for: .seconds(30))
      }
    }
    // The server's version never changes while it runs: asked until it
    // answers (a server that has only just started may not be ready yet).
    versionTask = Task { [weak self] in
      while !Task.isCancelled {
        let status = try? await client.getSystemStatus().ok.body.json
        guard let self, !Task.isCancelled else { return }
        if let status {
          self.serverVersion = status.version
          return
        }
        try? await Task.sleep(for: .seconds(2))
      }
    }
    // The listening port only changes in Settings, so a slow refresh is enough.
    settingsTask = Task { [weak self] in
      while !Task.isCancelled {
        let settings = try? await client.getConnectionSettings().ok.body.json
        guard let self, !Task.isCancelled else { return }
        if let settings { self.listenPort = settings.listenPort }
        try? await Task.sleep(for: .seconds(120))
      }
    }
  }

  private func disconnect() {
    store.stop()
    vpnTask?.cancel()
    vpnTask = nil
    settingsTask?.cancel()
    settingsTask = nil
    versionTask?.cancel()
    versionTask = nil
    serverVersion = nil
    actions = nil
    creationActions = nil
    settingsActions = nil
    connection = nil  // for the Logs window
  }

  /// Stops everything, waiting while the helper saves (for Quit).
  public func stop() async {
    phase = .saving
    disconnect()
    if let supervisor { await supervisor.stop() }
    watchTask?.cancel()
    watchTask = nil
    phase = .stopped
  }
}

// MARK: Backup and restore

extension AppSession: BackupSource {
  public var canUseBackups: Bool { supervisor != nil && settingsActions != nil && !isRestoring }

  public var backupDataFolder: URL? { supervisor?.dataFolder }

  public func makeBackup() async throws(UmbraError) -> Data {
    guard let settingsActions else {
      throw UmbraError(
        code: "not_connected", message: "Umbra isn't running, so there's nothing to back up.")
    }
    return try await settingsActions.backup()
  }

  /// Stops the helper (waiting while it saves), has Umbra restore the
  /// backup, then starts the helper again, on the restored data or, if
  /// Umbra refused, on the data it had. The window shows "Starting…"
  /// throughout. Only ever called once the person has confirmed it.
  public func restoreBackup(from file: URL) async -> BackupRestoreResult {
    guard let supervisor, !isRestoring else {
      return .refused(reason: "Restoring works only with Umbra's own server, one at a time.")
    }
    isRestoring = true
    phase = .starting
    disconnect()
    await supervisor.stop()
    let result = await supervisor.restoreBackup(from: file)
    isRestoring = false
    // A failure to start is reported through the states, which the window shows.
    try? await supervisor.start()
    return result
  }
}

extension AppSession: SettingsSource {
  public func listenForSettingsChanges(
    _ listener: @escaping @MainActor (String) -> Void
  ) -> SettingsSubscription {
    store.listenForSettingsChanges(listener)
  }
}

/// Connecting a development build to a running Umbra instead of the helper.
public enum DevAttach {
  /// The connection named by `UMBRA_DEV_ATTACH_URL` and `UMBRA_DEV_ATTACH_KEY`
  /// (an API key), if both are set and the address is a web address.
  public static func connection(from environment: [String: String]) -> Connection? {
    guard let text = environment["UMBRA_DEV_ATTACH_URL"], !text.isEmpty,
      let key = environment["UMBRA_DEV_ATTACH_KEY"], !key.isEmpty,
      let url = URL(string: text), url.scheme == "http" || url.scheme == "https", url.host() != nil
    else { return nil }
    return Connection(baseURL: url, credential: .apiKey(key))
  }
}

extension AppSession: VpnSettingsSource {
  public var liveTransfer: Components.Schemas.Transfer? { store.transfer }
  public var liveConnection: FeedConnectionState { store.state }
}
