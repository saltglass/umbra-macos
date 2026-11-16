import Foundation
import os

/// Starts, watches and stops the Umbra server program bundled in the app
/// (`Umbra.app/Contents/Helpers/umbra`).
///
/// - `start()` launches it on a free port on 127.0.0.1 with a fresh secret
///   launch token, waits until it answers, and returns the `Connection` to it.
/// - If it stops without being asked, it is started again (with a new token,
///   so a new `Connection`), up to 3 times in 5 minutes; after that it is
///   left stopped and the state says why.
/// - `stop()` asks it to stop (SIGTERM), waits up to 30 s while the engine
///   saves, then forces it (SIGKILL).
///
/// Its standard input is a pipe the app holds open, so even if the app is
/// force-quit or crashes, the helper notices and shuts itself down.
///
/// The current state is in `state`, and every change is sent to each
/// `states()` stream.
public actor HelperSupervisor {
  private let executable: URL
  private let environment: HelperEnvironment
  private let timings: HelperTimings
  private let log: HelperLog
  private var budget: RestartBudget

  public private(set) var state: HelperState = .stopped
  private var listeners: [UUID: AsyncStream<HelperState>.Continuation] = [:]

  /// The helper running now (or starting), if any.
  private var current: HelperProcess?
  /// Its token, kept only to hide it from error messages and log tails.
  private var currentToken = ""
  /// Goes up with every launch, so the end of an old run isn't mistaken
  /// for the end of the current one.
  private var generation = 0
  /// True between `start()` and `stop()`: the helper should be running.
  private var wanted = false
  /// True once the current run has answered; until then a launch is in
  /// progress and handles an early exit itself.
  private var ready = false
  /// The stop in progress, so calling `stop()` twice waits for the same one.
  private var stopping: Task<HelperExit?, Never>?
  /// The restore from a backup in progress, if any (see `restoreBackup`).
  private var restoring: Task<BackupRestoreResult, Never>?

  private static let logger = Logger(subsystem: "UmbraKit", category: "helper")

  /// - Parameters:
  ///   - executable: the helper program.
  ///   - environment: which data folder and flags (see `HelperEnvironment`).
  ///   - timings: waits and limits; tests shorten them.
  public init(executable: URL, environment: HelperEnvironment, timings: HelperTimings = .standard) {
    self.executable = executable
    self.environment = environment
    self.timings = timings
    self.log = HelperLog(url: environment.logFile)
    self.budget = RestartBudget(limit: timings.restartLimit, window: timings.restartWindow)
  }

  /// The helper's process number while it runs (for tests and diagnostics).
  public var processID: pid_t? { current?.pid }

  /// The data folder the helper uses.
  public nonisolated var dataFolder: URL { environment.dataFolder }

  /// A stream of states: the current one at once, then every change.
  public func states() -> AsyncStream<HelperState> {
    let (stream, continuation) = AsyncStream.makeStream(of: HelperState.self)
    let id = UUID()
    listeners[id] = continuation
    continuation.yield(state)
    continuation.onTermination = { [weak self] _ in
      Task { await self?.removeListener(id) }
    }
    return stream
  }

  private func removeListener(_ id: UUID) { listeners[id] = nil }

  private func publish(_ new: HelperState) {
    state = new
    for listener in listeners.values { listener.yield(new) }
  }

  // MARK: Start

  /// Starts the helper and waits until it answers. Returns at once with the
  /// current connection if it is already running.
  @discardableResult
  public func start() async throws(HelperError) -> Connection {
    if case .running(let connection) = state { return connection }
    if wanted, current != nil { return try await settled() }  // already starting
    if let stopping { _ = await stopping.value }
    if let restoring { _ = await restoring.value }
    wanted = true
    budget.reset()
    publish(.starting)
    do {
      let connection = try await launch()
      publish(.running(connection))
      return connection
    } catch {
      // If `stop()` cut the start short, it reports `.stopped` itself.
      let stopRequested = !wanted
      wanted = false
      if !stopRequested { publish(.failed(message: error.message, logTail: error.logTail)) }
      throw error
    }
  }

  /// Waits for a start already under way to finish.
  private func settled() async throws(HelperError) -> Connection {
    for await next in states() {
      switch next {
      case .running(let connection): return connection
      case .failed(let message, let logTail): throw HelperError(message: message, logTail: logTail)
      case .stopped:
        throw HelperError(message: "Umbra's server was stopped while starting.", logTail: [])
      case .starting, .restarting, .stopping: continue
      }
    }
    throw HelperError(message: "Umbra's server was stopped while starting.", logTail: [])
  }

  /// One launch: fresh token, folder ready, program started, waited for.
  private func launch() async throws(HelperError) -> Connection {
    try environment.checkAllowed()
    let token = try LaunchToken.make()
    let fm = FileManager.default
    let folder = environment.dataFolder
    do {
      // Readable by this user only: the database and the secret key live here.
      try fm.createDirectory(
        at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      try fm.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: folder.path(percentEncoded: false))
    } catch {
      throw HelperError(
        message:
          "Umbra's data folder couldn't be made (\(folder.path(percentEncoded: false))): \(error.localizedDescription)",
        logTail: [])
    }
    // An address left from an earlier run would point at a dead server.
    try? fm.removeItem(at: environment.addressFile)

    guard fm.isExecutableFile(atPath: executable.path(percentEncoded: false)) else {
      throw HelperError(
        message:
          "Umbra's server program is missing from the app (looked for \(executable.path(percentEncoded: false))). "
          + "Reinstalling Umbra should fix this.",
        logTail: [])
    }

    log.rotate(above: timings.logRotateBytes)
    log.note("started by the app at \(Date().formatted(.iso8601))")

    generation += 1
    ready = false
    currentToken = token
    let process: HelperProcess
    do {
      process = try HelperProcess.launch(
        executable: executable,
        environment: environment.processEnvironment(
          token: token, inherited: ProcessInfo.processInfo.environment),
        log: log)
    } catch {
      throw HelperError(
        message: "Umbra's server program couldn't be started: \(error.localizedDescription)",
        logTail: log.tail()
      ).hiding(token)
    }
    current = process
    let thisRun = generation
    Task { [weak self, watch = process.watch] in
      guard let exit = await watch.wait() else { return }
      await self?.ended(generation: thisRun, exit: exit)
    }

    do {
      let address = try await waitUntilAnswering(process)
      let connection = Connection(
        baseURL: URL(string: "http://\(address)")!, credential: .launchToken(token))
      // Tests' helpers each get a peer port of their own, so they can run
      // alongside each other and the development app (see PeerPort).
      if environment.kind == .testing { try await givePeerPort(to: connection) }
      ready = true
      Self.logger.info("Helper running at \(address, privacy: .public)")
      return connection
    } catch {
      // Don't leave a half-started helper behind.
      await terminate(process, grace: .seconds(2))
      if current === process { current = nil }
      throw error.hiding(token)
    }
  }

  /// Moves a test's helper to a peer port of its own, adding the end of
  /// its log to the error if that fails.
  private func givePeerPort(to connection: Connection) async throws(HelperError) {
    do {
      try await PeerPort.moveToFreePort(connection)
    } catch {
      throw HelperError(message: error.message, logTail: log.tail())
    }
  }

  /// Waits for the address file, then for /ping to answer, within the start timeout.
  private func waitUntilAnswering(_ process: HelperProcess) async throws(HelperError) -> String {
    let clock = ContinuousClock()
    let deadline = clock.now + timings.startTimeout
    while clock.now < deadline {
      if let exit = process.watch.exit {
        throw HelperError(
          message:
            "Umbra's server stopped while starting (\(exit.description)). The end of its log is below.",
          logTail: log.tail())
      }
      if !wanted {
        throw HelperError(message: "Umbra's server was stopped while starting.", logTail: [])
      }
      if let address = readAddress(), await Self.ping(address) {
        return address
      }
      try? await Task.sleep(for: timings.pollInterval)
    }
    let seconds = timings.startTimeout.components.seconds
    throw HelperError(
      message:
        "Umbra's server didn't answer within \(seconds) seconds of starting. The end of its log is below.",
      logTail: log.tail())
  }

  /// "127.0.0.1:51735" from the address file, once the helper has written it
  /// (it writes it in one go, so a partial address is never seen).
  private func readAddress() -> String? {
    guard let data = try? Data(contentsOf: environment.addressFile) else { return nil }
    let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    // Only ever a loopback address: the helper must never be reached from outside.
    guard text.hasPrefix("127.0.0.1:"), let port = Int(text.dropFirst(10)), port > 0 else {
      return nil
    }
    return text
  }

  /// A session that never goes through a proxy (127.0.0.1 is always direct).
  private static let pingSession: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.connectionProxyDictionary = [:]
    config.timeoutIntervalForRequest = 2
    return URLSession(configuration: config)
  }()

  /// Whether `GET /ping` answers 200. It needs no token.
  private static func ping(_ address: String) async -> Bool {
    guard let url = URL(string: "http://\(address)/ping") else { return false }
    let response = try? await pingSession.data(from: url).1
    return (response as? HTTPURLResponse)?.statusCode == 200
  }

  // MARK: Watch

  /// Called when a run ends, asked or not.
  private func ended(generation thisRun: Int, exit: HelperExit) async {
    guard thisRun == generation, let process = current else { return }
    // A launch still waiting for its helper notices the exit itself, and a
    // stop in progress handles its own ending.
    guard ready, stopping == nil else { return }
    process.closeStdin()
    current = nil
    guard wanted else {
      publish(.stopped)
      return
    }
    Self.logger.error("Helper stopped unexpectedly (\(exit.description, privacy: .public))")
    log.note("Umbra stopped unexpectedly (\(exit.description))")
    await restart(after: exit)
  }

  /// Starts it again, as long as the restart budget allows.
  private func restart(after exit: HelperExit) async {
    var lastError: HelperError?
    while wanted {
      guard let attempt = budget.take(at: timings.now()) else {
        wanted = false
        let minutes = Int(timings.restartWindow.components.seconds / 60)
        var message =
          "Umbra's server kept stopping: it was restarted \(timings.restartLimit) times in \(minutes) minutes "
          + "and stopped again, so it wasn't started again. The end of its log is below."
        if let lastError { message += " Last problem: \(lastError.message)" }
        publish(.failed(message: message, logTail: log.tail()))
        return
      }
      publish(.restarting(attempt: attempt))
      do {
        let connection = try await launch()
        guard wanted else { return }  // stopped while restarting; stop() reports it
        publish(.running(connection))
        return
      } catch {
        lastError = error
      }
    }
  }

  // MARK: Stop

  /// Asks the helper to stop and waits for it: SIGTERM, then SIGKILL if it
  /// hasn't ended within the grace time. Returns how it ended, or nil if
  /// nothing was running. Safe to call any number of times.
  @discardableResult
  public func stop() async -> HelperExit? {
    wanted = false
    if let stopping { return await stopping.value }
    guard let process = current else {
      if state != .stopped, !Self.isFailed(state) { publish(.stopped) }
      return nil
    }
    publish(.stopping)
    let grace = timings.stopGrace
    let task = Task { await self.terminate(process, grace: grace) }
    stopping = task
    let exit = await task.value
    process.closeStdin()
    if current === process { current = nil }
    stopping = nil
    publish(.stopped)
    return exit
  }

  @discardableResult
  private func terminate(_ process: HelperProcess, grace: Duration) async -> HelperExit? {
    process.signal(SIGTERM)
    if let exit = await process.watch.wait(upTo: grace) { return exit }
    Self.logger.error("Helper didn't stop within the grace time; forcing it")
    log.note("Umbra didn't stop in time and was forced to")
    process.signal(SIGKILL)
    return await process.watch.wait(upTo: .seconds(5))
  }

  private static func isFailed(_ state: HelperState) -> Bool {
    if case .failed = state { return true }
    return false
  }

  // MARK: Restore

  /// Restores a backup over the helper's data folder: Umbra's settings,
  /// its torrent list and its saved VPNs are replaced by the backup's
  /// (see `HelperRestore`). The helper must be stopped first (`stop()`);
  /// this refuses while it runs. It doesn't start the helper again: the
  /// caller does that, whatever the result, so Umbra carries on with the
  /// restored data, or with the old data if the restore was refused.
  ///
  /// The state reads `.starting` meanwhile, so the window shows its
  /// "Starting…" screen, then `.stopped`.
  public func restoreBackup(from file: URL) async -> BackupRestoreResult {
    if let restoring { return await restoring.value }
    guard !wanted, current == nil, stopping == nil else {
      return .refused(reason: "Umbra's server is still running. Stop it before restoring.")
    }
    do {
      try environment.checkAllowed()
    } catch {
      return .refused(reason: error.message)
    }
    publish(.starting)
    log.note("restoring from a backup at \(Date().formatted(.iso8601))")
    let task = Task { [executable, environment] in
      await HelperRestore.run(executable: executable, environment: environment, file: file)
    }
    restoring = task
    let result = await task.value
    restoring = nil
    switch result {
    case .restored(let kept):
      log.note("restored from a backup; the data from before is in \(kept ?? "(nothing to keep)")")
    case .refused(let reason):
      log.note("the backup wasn't restored: \(reason)")
    }
    if !wanted { publish(.stopped) }
    return result
  }

  // MARK: For tests

  /// Closes the helper's standard input as if the app had died, without
  /// asking it to stop, and says not to restart it (nobody would be left to).
  func simulateAppGone() -> pid_t? {
    wanted = false
    current?.closeStdin()
    return current?.pid
  }

  /// The current token, so tests can check it appears nowhere it shouldn't.
  var tokenForTesting: String { currentToken }
}
