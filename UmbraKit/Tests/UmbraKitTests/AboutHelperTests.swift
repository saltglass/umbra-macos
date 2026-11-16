import Foundation
import Testing

@testable import UmbraKit

/// The About window's server line against a real Umbra on 127.0.0.1, in a
/// temporary folder.
extension HelperIntegrationTests {
  /// The session asks the running helper for its version, and the About
  /// line then shows it; once the helper has stopped, the line says so.
  @Test func theSessionLearnsTheServersVersionForTheAboutWindow() async throws {
    try await withSupervisor { supervisor, _ in
      await Self.checkAboutLine(supervisor)
    }
  }

  @MainActor static func checkAboutLine(_ supervisor: HelperSupervisor) async {
    let session = AppSession(supervisor: supervisor)
    #expect(
      AboutInfo.serverLine(phase: session.phase, version: session.serverVersion)
        == "Umbra server: not running")
    session.start()
    #expect(await eventually { session.serverVersion != nil })
    let line = AboutInfo.serverLine(phase: session.phase, version: session.serverVersion)
    #expect(line.hasPrefix("Umbra server "), "\(line)")
    #expect(line != "Umbra server: not running")

    await session.stop()
    #expect(session.serverVersion == nil)
    #expect(
      AboutInfo.serverLine(phase: session.phase, version: session.serverVersion)
        == "Umbra server: not running")
  }
}
