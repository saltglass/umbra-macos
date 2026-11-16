import Foundation
import Testing

@testable import UmbraKit

/// Settings → General → "Opening torrents", over a fake that never asks macOS.
@MainActor @Suite struct DefaultAppModelTests {
  struct Refused: LocalizedError {
    var errorDescription: String? { "The application can't be changed." }
  }

  final class FakeService: DefaultAppService {
    var apps: [OpeningKind: DefaultAppReading] = [:]
    var failure: (any Error)?
    /// What the change does when it works: nothing, if false (macOS said no).
    var changeSticks = true
    private(set) var changes: [OpeningKind] = []

    func current(for kind: OpeningKind) -> DefaultAppReading? { apps[kind] }

    func makeDefault(for kind: OpeningKind) async throws {
      changes.append(kind)
      if let failure { throw failure }
      if changeSticks { apps[kind] = DefaultAppReading(name: "Umbra", isUmbra: true) }
    }
  }

  let other = DefaultAppReading(name: "qBittorrent", isUmbra: false)
  let umbra = DefaultAppReading(name: "Umbra", isUmbra: true)

  @Test func showsTheRightWordsForEachState() {
    let service = FakeService()
    service.apps = [.torrentFiles: umbra, .magnetLinks: other]
    let model = DefaultAppModel(service: service)
    #expect(model.status(for: .torrentFiles) == "Umbra is the default")
    #expect(model.status(for: .magnetLinks) == "Opens in qBittorrent")
    service.apps[.magnetLinks] = nil
    model.refresh()
    #expect(model.status(for: .magnetLinks) == "No default app")
  }

  @Test func theButtonIsOnlyForWhenUmbraIsNotTheDefault() {
    let service = FakeService()
    service.apps = [.torrentFiles: umbra, .magnetLinks: other]
    let model = DefaultAppModel(service: service)
    #expect(!model.canMakeDefault(.torrentFiles))
    #expect(model.canMakeDefault(.magnetLinks))
  }

  @Test func makingItTheDefaultAsksOnceAndShowsTheNewState() async {
    let service = FakeService()
    service.apps = [.torrentFiles: other]
    let model = DefaultAppModel(service: service)
    await model.makeDefault(.torrentFiles)
    #expect(service.changes == [.torrentFiles])
    #expect(model.status(for: .torrentFiles) == "Umbra is the default")
    #expect(model.problem(for: .torrentFiles) == nil)
    // Now that it is the default, pressing again asks nothing more.
    await model.makeDefault(.torrentFiles)
    #expect(service.changes == [.torrentFiles])
  }

  @Test func theOtherKindIsLeftAlone() async {
    let service = FakeService()
    service.apps = [.torrentFiles: other, .magnetLinks: other]
    let model = DefaultAppModel(service: service)
    await model.makeDefault(.magnetLinks)
    #expect(model.status(for: .magnetLinks) == "Umbra is the default")
    #expect(model.status(for: .torrentFiles) == "Opens in qBittorrent")
  }

  @Test func aFailureIsShownUnderItsRowOnly() async {
    let service = FakeService()
    service.apps = [.torrentFiles: other, .magnetLinks: other]
    service.failure = Refused()
    let model = DefaultAppModel(service: service)
    await model.makeDefault(.torrentFiles)
    #expect(
      model.problem(for: .torrentFiles)
        == "macOS wouldn't change it. The application can't be changed.")
    #expect(model.problem(for: .magnetLinks) == nil)
    #expect(model.status(for: .torrentFiles) == "Opens in qBittorrent")
    // Trying again clears the old message first.
    service.failure = nil
    await model.makeDefault(.torrentFiles)
    #expect(model.problem(for: .torrentFiles) == nil)
  }

  @Test func aChangeMacOSSilentlyDeclinesIsSaid() async {
    let service = FakeService()
    service.apps = [.magnetLinks: other]
    service.changeSticks = false
    let model = DefaultAppModel(service: service)
    await model.makeDefault(.magnetLinks)
    #expect(model.problem(for: .magnetLinks)?.hasPrefix("macOS didn't change it.") == true)
    #expect(model.status(for: .magnetLinks) == "Opens in qBittorrent")
  }
}
