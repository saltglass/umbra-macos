import Foundation
import Testing
import UmbraAPI

@testable import UmbraKit

/// Saving and restoring a backup against a real Umbra on 127.0.0.1, in a
/// temporary folder (never the real data folder), with no torrents and no
/// network beyond this Mac.
extension HelperIntegrationTests {
  /// Saves a backup through the Backup section's model, changes a setting,
  /// restores, and sees the old setting back; the helper went stop →
  /// restore → start, and the data from before is kept in the data folder.
  @Test func aBackupRestoresTheSettingsItWasMadeWith() async throws {
    try await withSupervisor { supervisor, environment in
      let folder = try makeTempFolder()
      defer { try? FileManager.default.removeItem(at: folder) }
      let file = folder.appending(path: "Umbra backup.tar.gz")
      try await Self.backupThenRestore(supervisor, environment.dataFolder, file)
    }
  }

  @MainActor static func backupThenRestore(
    _ supervisor: HelperSupervisor, _ dataFolder: URL, _ file: URL
  ) async throws {
    let session = AppSession(supervisor: supervisor)
    session.start()
    #expect(await eventually { session.settingsActions != nil })
    let model = BackupModel(source: session)
    #expect(model.isEnabled)

    // The setting as the backup has it.
    var downloads = try await session.settingsActions!.downloads()
    downloads.lowSpaceWarningGB = 11
    _ = try await session.settingsActions!.setDownloads(downloads)

    await model.save(to: file)
    #expect(model.problem == nil)
    let attributes = try FileManager.default.attributesOfItem(
      atPath: file.path(percentEncoded: false))
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

    // Changed afterwards.
    downloads.lowSpaceWarningGB = 22
    _ = try await session.settingsActions!.setDownloads(downloads)

    // Every state the helper goes through while restoring.
    let states = await supervisor.states()
    let seen = Task { () -> [String] in
      var names: [String] = []
      for await state in states {
        names.append(Self.name(state))
        if names.count > 1, case .running = state { break }
      }
      return names
    }

    model.askToRestore(file)
    await model.confirmRestore()
    #expect(model.problem == nil, "\(model.problem ?? "")")
    #expect(model.status?.hasPrefix("Restored from “Umbra backup.tar.gz”.") == true)

    // Stop (waiting while it saves), restore, start again.
    let order = await seen.value
    #expect(
      order == ["running", "stopping", "stopped", "starting", "stopped", "starting", "running"])

    #expect(await eventually { session.settingsActions != nil && session.phase == .running })
    let back = try await session.settingsActions!.downloads()
    #expect(back.lowSpaceWarningGB == 11)

    // The data from before is kept inside the data folder.
    let kept = try FileManager.default.contentsOfDirectory(
      atPath: dataFolder.path(percentEncoded: false)
    )
    .filter { $0.hasPrefix("before-restore-") }
    #expect(kept.count == 1)
    if let name = kept.first {
      #expect(
        FileManager.default.fileExists(
          atPath: dataFolder.appending(path: "\(name)/umbra.db").path(percentEncoded: false)))
    }
    await session.stop()
  }

  /// A file that isn't a backup is refused with Umbra's reason, nothing is
  /// changed, and the helper is started again on the data it had.
  @Test func aRefusedRestoreStartsAgainOnTheOldData() async throws {
    try await withSupervisor { supervisor, environment in
      let folder = try makeTempFolder()
      defer { try? FileManager.default.removeItem(at: folder) }
      let file = folder.appending(path: "not a backup.tar.gz")
      try Data("this is not one of Umbra's backups".utf8).write(to: file)
      try await Self.refusedRestore(supervisor, environment.dataFolder, file)
    }
  }

  @MainActor static func refusedRestore(
    _ supervisor: HelperSupervisor, _ dataFolder: URL, _ file: URL
  ) async throws {
    let session = AppSession(supervisor: supervisor)
    session.start()
    #expect(await eventually { session.settingsActions != nil })
    var downloads = try await session.settingsActions!.downloads()
    downloads.lowSpaceWarningGB = 33
    _ = try await session.settingsActions!.setDownloads(downloads)

    let model = BackupModel(source: session)
    model.askToRestore(file)
    await model.confirmRestore()
    let problem = try #require(model.problem)
    #expect(problem.hasPrefix("The backup wasn't restored, and nothing was changed. "))
    #expect(problem.contains("isn't one of Umbra's backups"))
    #expect(problem.hasSuffix("Umbra started again with the settings it had."))

    #expect(await eventually { session.settingsActions != nil && session.phase == .running })
    #expect(try await session.settingsActions!.downloads().lowSpaceWarningGB == 33)
    let kept = try FileManager.default.contentsOfDirectory(
      atPath: dataFolder.path(percentEncoded: false)
    )
    .filter { $0.hasPrefix("before-restore-") || $0.hasPrefix(".") && $0.contains("restoring") }
    #expect(kept.isEmpty)
    await session.stop()
  }

  /// With the real app's hold on: the hold follows the backup. A backup
  /// made before "Start without VPN" was chosen (and with no VPN) brings
  /// the hold back after a restore, even though the choice had been made
  /// since: nothing touches the network until a VPN is set up or the
  /// choice is made again.
  @Test func aRestoreBringsBackTheBackupsVpnChoice() async throws {
    try await withSupervisor(holdUntilVpn: true) { supervisor, _ in
      let folder = try makeTempFolder()
      defer { try? FileManager.default.removeItem(at: folder) }
      try await Self.holdFollowsTheBackup(supervisor, folder.appending(path: "held.tar.gz"))
    }
  }

  @MainActor static func holdFollowsTheBackup(_ supervisor: HelperSupervisor, _ file: URL)
    async throws
  {
    let session = AppSession(supervisor: supervisor)
    session.start()
    #expect(await eventually { session.settingsActions != nil })
    #expect(try await session.settingsActions!.vpn().heldReason == .noVpnYet)
    let model = BackupModel(source: session)
    await model.save(to: file)
    #expect(model.problem == nil)

    try await session.settingsActions!.startWithoutVpn()
    #expect(try await session.settingsActions!.vpn().state != .held)

    model.askToRestore(file)
    await model.confirmRestore()
    #expect(model.problem == nil)
    #expect(await eventually { session.settingsActions != nil && session.phase == .running })
    let after = try await session.settingsActions!.vpn()
    #expect(after.state == .held)
    #expect(after.heldReason == .noVpnYet)
    await session.stop()
  }

  /// The supervisor won't restore while its helper runs.
  @Test func noRestoreWhileTheHelperRuns() async throws {
    try await withSupervisor { supervisor, _ in
      _ = try await supervisor.start()
      let result = await supervisor.restoreBackup(from: URL(filePath: "/nonexistent.tar.gz"))
      #expect(
        result == .refused(reason: "Umbra's server is still running. Stop it before restoring."))
      if case .running = await supervisor.state {} else { Issue.record("the helper isn't running") }
    }
  }

  static func name(_ state: HelperState) -> String {
    switch state {
    case .stopped: "stopped"
    case .starting: "starting"
    case .running: "running"
    case .restarting: "restarting"
    case .stopping: "stopping"
    case .failed: "failed"
    }
  }
}
