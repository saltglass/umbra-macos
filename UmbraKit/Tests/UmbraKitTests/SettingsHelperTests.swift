import Foundation
import Testing
import UmbraAPI

@testable import UmbraKit

extension HelperIntegrationTests {
  /// A Queue and a Seeding change made through the settings models reach a
  /// real Umbra (on 127.0.0.1, in a temporary folder) and read back; a
  /// value Umbra refuses goes back, with Umbra's own message.
  @Test func settingsChangesReachUmbraAndReadBack() async throws {
    try await withSupervisor { supervisor, _ in
      try await Self.changeSettings(on: try await supervisor.start())
    }
  }

  @MainActor static func changeSettings(on connection: Connection) async throws {
    do {
      let source = FakeSettingsSource(connected: false)
      source.settingsActions = SettingsActions(connection: connection)
      let models = SettingsModels(source: source)
      let queue = models.model(for: .queue)
      let seeding = models.model(for: .seeding)
      #expect(await eventually { queue.phase == .loaded && seeding.phase == .loaded })

      // A typed field, committed.
      queue.type("7", into: \.maxActiveDownloads)
      queue.commit(\.maxActiveDownloads, as: .wholeNumber())
      // Hours, kept as minutes.
      seeding.type("1.5", into: \.seedingMinutes)
      seeding.commit(\.seedingMinutes, as: .optionalHoursAsMinutes())
      #expect(await eventually { !queue.isSending && !seeding.isSending })

      // Read back with a fresh request, not through the models.
      let reader = SettingsActions(connection: connection)
      #expect(try await reader.queue().maxActiveDownloads == 7)
      #expect(try await reader.seeding().seedingMinutes == 90)

      // Umbra refuses 0 downloads at once; the field goes back and says why.
      queue.set(\.maxActiveDownloads, to: 0)
      #expect(await eventually { queue.refusal != nil })
      #expect(queue.value?.maxActiveDownloads == 7)
      #expect(queue.problem(for: "maxActiveDownloads") == "Enter a number from 1 to 50.")
      #expect(try await reader.queue().maxActiveDownloads == 7)
    }
  }
}
