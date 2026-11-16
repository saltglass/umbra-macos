import Foundation
import Testing

@testable import UmbraKit

/// A fresh empty folder for one test, removed afterwards by the caller.
func makeTempFolder() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "umbra-test-\(UUID().uuidString)", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

@Suite struct HelperEnvironmentTests {
  let support = URL(
    filePath: "/Users/someone/Library/Application Support", directoryHint: .isDirectory)

  @Test func releaseUsesTheUmbraFolderAndTalksToTheWorld() throws {
    let env = HelperEnvironment.release(applicationSupport: support)
    #expect(env.dataFolder.path() == "/Users/someone/Library/Application%20Support/Umbra/")
    #expect(!env.loopbackOnly)
    let vars = env.processEnvironment(token: "t", inherited: [:])
    #expect(vars["UMBRA_LOOPBACK_ONLY"] == nil)
    // The real app holds every torrent until a VPN is chosen.
    #expect(env.holdUntilVpn)
    #expect(vars["UMBRA_HOLD_UNTIL_VPN"] == "true")
  }

  @Test func developmentUsesItsOwnFolderAndStaysOnLoopback() throws {
    let env = HelperEnvironment.development(applicationSupport: support)
    #expect(env.dataFolder.lastPathComponent == "Umbra-Dev")
    #expect(env.loopbackOnly)
    #expect(env.processEnvironment(token: "t", inherited: [:])["UMBRA_LOOPBACK_ONLY"] == "true")
    // Development keeps today's behaviour: no hold.
    #expect(env.processEnvironment(token: "t", inherited: [:])["UMBRA_HOLD_UNTIL_VPN"] == nil)
    try env.checkAllowed()
  }

  @Test func testingIsLoopbackOnly() {
    let env = HelperEnvironment.testing(dataFolder: URL(filePath: "/tmp/x"))
    #expect(env.processEnvironment(token: "t", inherited: [:])["UMBRA_LOOPBACK_ONLY"] == "true")
    #expect(env.processEnvironment(token: "t", inherited: [:])["UMBRA_HOLD_UNTIL_VPN"] == nil)
    // A test can turn the hold on; it stays loopback-only.
    let held = HelperEnvironment.testing(dataFolder: URL(filePath: "/tmp/x"), holdUntilVpn: true)
    let vars = held.processEnvironment(token: "t", inherited: ["UMBRA_HOLD_UNTIL_VPN": "false"])
    #expect(vars["UMBRA_HOLD_UNTIL_VPN"] == "true")
    #expect(vars["UMBRA_LOOPBACK_ONLY"] == "true")
  }

  /// Pins the rule that nothing but a release build may use the real data
  /// folder: the folder itself, anything inside it, or a folder holding it.
  @Test func nonReleaseEnvironmentsAreRefusedTheReleaseFolder() throws {
    let real = HelperEnvironment.releaseFolder()
    for folder in [
      real,
      URL(filePath: real.path(percentEncoded: false) + "/"),
      real.appending(path: "sub"),
      real.appending(path: "x/../"),
      real.deletingLastPathComponent(),
    ] {
      #expect(throws: HelperError.self, "\(folder.path())") {
        try HelperEnvironment.testing(dataFolder: folder).checkAllowed()
      }
    }
    // The real development folder sits next to it and is fine.
    try HelperEnvironment.development().checkAllowed()
  }

  @Test func refusalFollowsSymbolicLinks() throws {
    let temp = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: temp) }
    let link = temp.appending(path: "sneaky")
    // A link to the real folder: never followed into, only compared.
    try FileManager.default.createSymbolicLink(
      at: link, withDestinationURL: HelperEnvironment.releaseFolder())
    #expect(throws: HelperError.self) {
      try HelperEnvironment.testing(dataFolder: link).checkAllowed()
    }
  }

  @Test func resolvingFollowsRelativeAndChainedLinks() throws {
    let temp = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: temp) }
    let fm = FileManager.default
    try fm.createSymbolicLink(atPath: temp.appending(path: "a").path(), withDestinationPath: "b/c")
    try fm.createSymbolicLink(atPath: temp.appending(path: "b").path(), withDestinationPath: "/x/y")
    try fm.createSymbolicLink(
      atPath: temp.appending(path: "loop").path(), withDestinationPath: "loop")
    #expect(HelperEnvironment.resolved(temp.appending(path: "a/d")) == ["/", "x", "y", "c", "d"])
    _ = HelperEnvironment.resolved(temp.appending(path: "loop"))  // ends
  }

  @Test func helperGetsTheSettingsItNeedsAndNoStrayUmbraVariables() {
    let env = HelperEnvironment.testing(dataFolder: URL(filePath: "/tmp/umbra-x"))
    let vars = env.processEnvironment(
      token: "tok",
      inherited: ["PATH": "/usr/bin", "UMBRA_DEV_ATTACH_KEY": "secret", "UMBRA_PORT": "1"])
    #expect(vars["PATH"] == "/usr/bin")
    #expect(vars["UMBRA_DEV_ATTACH_KEY"] == nil)
    #expect(vars["UMBRA_PORT"] == nil)
    #expect(vars["UMBRA_DATA_DIR"] == "/tmp/umbra-x")
    #expect(vars["UMBRA_LISTEN"] == "127.0.0.1:0")
    #expect(vars["UMBRA_ADDR_FILE"] == "/tmp/umbra-x/helper-address")
    #expect(vars["UMBRA_LAUNCH_TOKEN"] == "tok")
    #expect(vars["UMBRA_EXIT_WITH_PARENT"] == "true")
    #expect(vars["UMBRA_SHARE_ANYWHERE"] == "true")
  }

  @Test func launchTokensAreLongRandomAndHex() throws {
    let a = try LaunchToken.make()
    let b = try LaunchToken.make()
    #expect(a.count == 64)
    #expect(a != b)
    #expect(a.allSatisfy { $0.isHexDigit })
  }
}

@Suite struct HelperLogTests {
  @Test func bigLogIsMovedAsideAtStart() throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let log = HelperLog(url: folder.appending(path: "helper.log"))
    try Data("old old\n".utf8).write(to: log.previousURL)
    try Data(repeating: 0x41, count: 2000).write(to: log.url)

    log.rotate(above: 1000)
    #expect(!FileManager.default.fileExists(atPath: log.url.path()))
    #expect(try Data(contentsOf: log.previousURL).count == 2000)  // the older .1 is gone
  }

  @Test func smallLogIsKept() throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let log = HelperLog(url: folder.appending(path: "helper.log"))
    try Data("short\n".utf8).write(to: log.url)
    log.rotate(above: 1000)
    #expect(log.tail() == ["short"])
    #expect(!FileManager.default.fileExists(atPath: log.previousURL.path()))
  }

  @Test func tailIsTheLastLines() throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let log = HelperLog(url: folder.appending(path: "helper.log"))
    try Data((1...100).map { "line \($0)\n" }.joined().utf8).write(to: log.url)
    log.note("marker")
    #expect(log.tail(3) == ["line 99", "line 100", "--- marker ---"])
    #expect(HelperLog(url: folder.appending(path: "none")).tail() == [])
  }

  @Test func errorsHideTheToken() {
    let error = HelperError(message: "bad abc123 here", logTail: ["x abc123", "y"]).hiding("abc123")
    #expect(error.message == "bad <hidden> here")
    #expect(error.logTail == ["x <hidden>", "y"])
  }
}

@Suite struct RestartBudgetTests {
  @Test func threeRestartsInFiveMinutesThenNoMore() {
    var budget = RestartBudget(limit: 3, window: .seconds(300))
    let t0 = ContinuousClock.now
    #expect(budget.take(at: t0) == 1)
    #expect(budget.take(at: t0 + .seconds(10)) == 2)
    #expect(budget.take(at: t0 + .seconds(20)) == 3)
    #expect(budget.take(at: t0 + .seconds(30)) == nil)
    // Once the first falls out of the 5-minute window, one more is allowed.
    #expect(budget.take(at: t0 + .seconds(300)) == 3)
    budget.reset()
    #expect(budget.take(at: t0 + .seconds(301)) == 1)
  }

  @Test func spreadOutCrashesAreAlwaysRestarted() {
    var budget = RestartBudget(limit: 3, window: .seconds(300))
    let t0 = ContinuousClock.now
    for hour in 0..<10 {
      #expect(budget.take(at: t0 + .seconds(hour * 3600)) == 1)
    }
  }
}

@Suite struct DevAttachTests {
  @Test func needsBothSettings() {
    #expect(DevAttach.connection(from: [:]) == nil)
    #expect(DevAttach.connection(from: ["UMBRA_DEV_ATTACH_URL": "http://127.0.0.1:7980"]) == nil)
    #expect(
      DevAttach.connection(from: ["UMBRA_DEV_ATTACH_URL": "nonsense", "UMBRA_DEV_ATTACH_KEY": "k"])
        == nil)
    let connection = DevAttach.connection(from: [
      "UMBRA_DEV_ATTACH_URL": "http://127.0.0.1:7980", "UMBRA_DEV_ATTACH_KEY": "k",
    ])
    #expect(connection?.credential == .apiKey("k"))
    #expect(connection?.serverURL.absoluteString == "http://127.0.0.1:7980/api/v1")
  }
}
