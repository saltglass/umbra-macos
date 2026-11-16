import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
import UmbraAPI

@testable import UmbraKit

/// The real helper program, built by `just helper` into `<repo>/build/helper/umbra`.
let helperBinary: URL = URL(filePath: #filePath)
  .deletingLastPathComponent()  // UmbraKitTests
  .deletingLastPathComponent()  // Tests
  .deletingLastPathComponent()  // UmbraKit
  .deletingLastPathComponent()  // the repo
  .appending(path: "build/helper/umbra")

let helperIsBuilt = FileManager.default.isExecutableFile(
  atPath: helperBinary.path(percentEncoded: false))

/// Tests against the real Umbra server program.
///
/// They run side by side, and alongside a development app's own helper:
/// each test's helper is moved to a peer port of its own once it is up
/// (see `PeerPort`), instead of Umbra's usual 6881. Each uses its own
/// temporary data folder, always loopback-only, and stops its helper
/// however the test ends; and since every helper's standard input is held by
/// this test process, any left over would shut down when it exits anyway.
@Suite(
  .timeLimit(.minutes(1)),
  .enabled(
    if: helperIsBuilt, "The Umbra helper isn't built: run `just helper` (with UMBRA_SRC set) first."
  )
)
struct HelperIntegrationTests {
  /// Short waits, so the suite stays quick.
  static var fastTimings: HelperTimings {
    var timings = HelperTimings()
    timings.startTimeout = .seconds(15)
    timings.pollInterval = .milliseconds(20)
    timings.stopGrace = .seconds(25)
    return timings
  }

  /// Runs `body` with a supervisor on a temporary folder, then always stops
  /// it, checks no helper is left, and removes the folder.
  func withSupervisor(
    executable: URL = helperBinary,
    timings: HelperTimings = fastTimings,
    holdUntilVpn: Bool = false,
    _ body: (HelperSupervisor, HelperEnvironment) async throws -> Void
  ) async throws {
    let folder = try makeTempFolder()
    let environment = HelperEnvironment.testing(dataFolder: folder, holdUntilVpn: holdUntilVpn)
    #expect(environment.loopbackOnly)
    let supervisor = HelperSupervisor(
      executable: executable, environment: environment, timings: timings)
    var failure: (any Error)?
    do { try await body(supervisor, environment) } catch { failure = error }
    let pid = await supervisor.processID
    await supervisor.stop()
    if let pid { #expect(await processGone(pid), "the helper was left running") }
    try? FileManager.default.removeItem(at: folder)
    if let failure { throw failure }
  }

  @Test func comesUpAndOnlyAnswersItsOwner() async throws {
    try await withSupervisor { supervisor, environment in
      let connection = try await supervisor.start()
      #expect(connection.baseURL.host() == "127.0.0.1")
      #expect(await supervisor.state == .running(connection))

      let ping = try await URLSession.shared.data(from: connection.baseURL.appending(path: "ping"))
      #expect((ping.1 as? HTTPURLResponse)?.statusCode == 200)

      // With the token: the list (empty in a new folder).
      let list = try await connection.makeClient().listTorrents()
      #expect(try list.ok.body.json.torrents.isEmpty)

      // With a wrong token: turned away.
      let wrong = Connection(
        baseURL: connection.baseURL, credential: .launchToken(String(repeating: "0", count: 64)))
      let refused = try await wrong.makeClient().listTorrents()
      guard case .unauthorized = refused else {
        Issue.record("expected 401, got \(refused)")
        return
      }

      // The data folder is private.
      let attributes = try FileManager.default.attributesOfItem(
        atPath: environment.dataFolder.path())
      #expect((attributes[.posixPermissions] as? Int) == 0o700)
    }
  }

  @Test func twoHelpersRunSideBySideOnTheirOwnPeerPorts() async throws {
    try await withSupervisor { first, _ in
      try await withSupervisor { second, _ in
        let one = try await first.start()
        let two = try await second.start()
        var ports: [Int] = []
        for connection in [one, two] {
          let client = connection.makeClient()
          // The engine runs (the list answers rather than "engine down")...
          #expect(try await client.listTorrents().ok.body.json.torrents.isEmpty)
          // ...on a port of its own, not Umbra's usual one.
          ports.append(try await client.getConnectionSettings().ok.body.json.listenPort)
        }
        #expect(!ports.contains(6881))
        #expect(ports[0] != ports[1])
      }
    }
  }

  @Test func stopEndsItCleanly() async throws {
    try await withSupervisor { supervisor, _ in
      try await supervisor.start()
      let pid = try #require(await supervisor.processID)
      let exit = await supervisor.stop()
      #expect(exit == .exited(code: 0))
      #expect(await processGone(pid))
      #expect(await supervisor.state == .stopped)
      #expect(await supervisor.stop() == nil)  // a second stop is harmless
    }
  }

  @Test func restartsAfterACrashWithANewConnection() async throws {
    try await withSupervisor { supervisor, _ in
      let first = try await supervisor.start()
      let states = await supervisor.states()
      let pid = try #require(await supervisor.processID)
      kill(pid, SIGKILL)

      let second = try await nextRunning(states, after: first)
      #expect(second.credential != first.credential)  // a new token
      #expect(await supervisor.processID != pid)
      #expect(try await second.makeClient().listTorrents().ok.body.json.torrents.isEmpty)
      // The old token no longer works.
      let stale = Connection(baseURL: second.baseURL, credential: first.credential)
      guard case .unauthorized = try await stale.makeClient().listTorrents() else {
        Issue.record("the old token still works")
        return
      }
    }
  }

  @Test func givesUpAfterTooManyRestarts() async throws {
    var timings = Self.fastTimings
    timings.restartLimit = 2  // two restarts are enough to prove the limit, and quicker
    try await withSupervisor(timings: timings) { supervisor, _ in
      var connection = try await supervisor.start()
      let states = await supervisor.states()
      for _ in 0..<2 {
        kill(try #require(await supervisor.processID), SIGKILL)
        connection = try await nextRunning(states, after: connection)
      }
      kill(try #require(await supervisor.processID), SIGKILL)
      for await state in states {
        if case .failed(let message, _) = state {
          #expect(message.contains("kept stopping"))
          break
        }
      }
      #expect(await supervisor.processID == nil)
    }
  }

  @Test func exitsByItselfWhenTheAppGoes() async throws {
    try await withSupervisor { supervisor, _ in
      try await supervisor.start()
      let pid = try #require(await supervisor.simulateAppGone())
      #expect(await processGone(pid, within: .seconds(25)))
      #expect(await eventuallyAsync { await supervisor.state == .stopped })
    }
  }

  @Test func aMissingProgramFailsReadably() async throws {
    let bogus = URL(filePath: "/nonexistent/umbra")
    try await withSupervisor(executable: bogus) { supervisor, _ in
      do {
        try await supervisor.start()
        Issue.record("started a program that doesn't exist")
      } catch let error as HelperError {
        #expect(error.message.contains("missing"))
        #expect(error.message.contains("/nonexistent/umbra"))
      }
      guard case .failed(let message, _) = await supervisor.state else {
        Issue.record("not failed")
        return
      }
      #expect(message.contains("missing"))
    }
  }

  @Test func aProgramThatDiesAtOnceFailsWithItsLog() async throws {
    // `false` exits at once with code 1, like a helper that crashes on start.
    try await withSupervisor(executable: URL(filePath: "/usr/bin/false")) {
      supervisor, environment in
      do {
        try await supervisor.start()
        Issue.record("started")
      } catch let error as HelperError {
        #expect(error.message.contains("stopped while starting"))
        #expect(error.message.contains("exit code 1"))
        #expect(error.logTail.last?.contains("started by the app") == true)
      }
    }
  }

  @Test func theTokenIsNowhereInErrorsOrTheLog() async throws {
    try await withSupervisor { supervisor, environment in
      let connection = try await supervisor.start()
      guard case .launchToken(let token) = connection.credential else {
        Issue.record("not a launch token")
        return
      }
      // Make the helper log a refused and an accepted request.
      _ = try await connection.makeClient().listTorrents()
      await supervisor.stop()
      let log = try String(contentsOf: environment.logFile, encoding: .utf8)
      #expect(log.contains("umbra started"))
      #expect(!log.contains(token))
      #expect(!"\(connection)".contains(token))
      // Nothing else in the folder holds it either.
      let files = try FileManager.default.subpathsOfDirectory(atPath: environment.dataFolder.path())
      for file in files {
        let data = (try? Data(contentsOf: environment.dataFolder.appending(path: file))) ?? Data()
        #expect(data.range(of: Data(token.utf8)) == nil, "token found in \(file)")
      }
    }
  }

  @Test func errorsCarryNoToken() async throws {
    // A launch that fails after the token was made: the error is scrubbed.
    try await withSupervisor(executable: URL(filePath: "/usr/bin/false")) { supervisor, _ in
      do {
        try await supervisor.start()
      } catch let error as HelperError {
        let token = await supervisor.tokenForTesting
        #expect(!token.isEmpty)
        #expect(!error.message.contains(token))
        #expect(!error.logTail.joined().contains(token))
      }
    }
  }
}

/// Waits for the next `.running` with a connection other than `previous`.
func nextRunning(_ states: AsyncStream<HelperState>, after previous: Connection) async throws
  -> Connection
{
  for await state in states {
    switch state {
    case .running(let connection) where connection != previous: return connection
    case .failed(let message, let tail):
      throw HelperError(message: message, logTail: tail)
    default: continue
    }
  }
  throw HelperError(message: "state stream ended", logTail: [])
}

/// Whether process `pid` has ended (checking for up to `within`).
func processGone(_ pid: pid_t, within limit: Duration = .seconds(5)) async -> Bool {
  let deadline = ContinuousClock.now + limit
  while ContinuousClock.now < deadline {
    if kill(pid, 0) != 0 && errno == ESRCH { return true }
    try? await Task.sleep(for: .milliseconds(20))
  }
  return false
}

/// Waits until `condition` holds, for up to five seconds.
func eventuallyAsync(_ condition: () async -> Bool) async -> Bool {
  for _ in 0..<250 {
    if await condition() { return true }
    try? await Task.sleep(for: .milliseconds(20))
  }
  return await condition()
}
