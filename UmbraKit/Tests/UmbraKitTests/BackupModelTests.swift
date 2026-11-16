import Foundation
import Testing

@testable import UmbraKit

/// A stand-in for the app's session: hands over a made-up backup and
/// notes every restore asked for, without any Umbra.
@MainActor
final class FakeBackupSource: BackupSource {
  var canUseBackups = true
  var backupDataFolder: URL? = URL(
    filePath: "/Users/someone/Library/Application Support/Umbra-Test")
  var backup: Result<Data, UmbraError> = .success(Data("made-up backup".utf8))
  var restoreResult: BackupRestoreResult = .restored(
    keptIn: "/tmp/data/before-restore-2026-11-14-184000")
  private(set) var backupsMade = 0
  private(set) var restoresAsked: [URL] = []

  func makeBackup() async throws(UmbraError) -> Data {
    backupsMade += 1
    return try backup.get()
  }

  func restoreBackup(from file: URL) async -> BackupRestoreResult {
    restoresAsked.append(file)
    return restoreResult
  }
}

@MainActor
struct BackupModelTests {
  let file = URL(filePath: "/Users/someone/Desktop/Umbra backup 2026-11-14 18.40.tar.gz")

  @Test func theWordsThePersonSees() {
    #expect(BackupModel.saveButton == "Save a Backup…")
    #expect(BackupModel.restoreButton == "Restore from Backup…")
    #expect(
      BackupModel.contents
        == "A backup holds Umbra's settings, the torrent list and the saved VPNs. It doesn't hold the downloaded files themselves."
    )
    #expect(
      BackupModel.alertTitle == "Replace Umbra's settings and torrent list with the backup's?")
    #expect(BackupModel.alertCancel == "Cancel")
    #expect(BackupModel.alertConfirm == "Replace")

    let model = BackupModel(source: FakeBackupSource())
    model.askToRestore(file)
    let message = model.alertMessage
    #expect(message.contains("replaced by the ones in “Umbra backup 2026-11-14 18.40.tar.gz”"))
    #expect(message.contains("Downloaded files aren't touched."))
    #expect(message.contains("kept in a folder named “before-restore-”"))
    #expect(message.contains("Umbra-Test"))
    #expect(message.contains("Umbra stops while it restores, then starts again."))
  }

  @Test func theSuggestedNameHasTheDateAndUmbrasFileType() {
    let date = Date(timeIntervalSince1970: 1_794_681_600)  // 2026-11-14 18:40 UTC
    #expect(
      BackupModel.suggestedFileName(at: date, timeZone: TimeZone(identifier: "UTC")!)
        == "Umbra backup 2026-11-14 18.40.tar.gz")
  }

  @Test func nothingWorksWhileNotConnected() async {
    let source = FakeBackupSource()
    source.canUseBackups = false
    let model = BackupModel(source: source)
    #expect(!model.isEnabled)
    await model.save(to: FileManager.default.temporaryDirectory.appending(path: "never"))
    model.askToRestore(file)
    await model.confirmRestore()
    #expect(source.backupsMade == 0)
    #expect(source.restoresAsked.isEmpty)
    #expect(model.pendingRestore == nil)
  }

  @Test func savingWritesWhatUmbraGaveReadableByThisUserOnly() async throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appending(path: "Umbra backup.tar.gz")
    // A file already there (the save panel asked to replace it) is replaced,
    // and loses its wider permissions.
    FileManager.default.createFile(
      atPath: target.path(percentEncoded: false), contents: Data("old".utf8),
      attributes: [.posixPermissions: 0o644])

    let source = FakeBackupSource()
    let model = BackupModel(source: source)
    await model.save(to: target)
    #expect(try Data(contentsOf: target) == Data("made-up backup".utf8))
    let attributes = try FileManager.default.attributesOfItem(
      atPath: target.path(percentEncoded: false))
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    #expect(model.status == "Saved “Umbra backup.tar.gz”.")
    #expect(model.problem == nil)
    #expect(model.activity == .idle)
    // Nothing half-written left beside it.
    #expect(
      try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Umbra backup.tar.gz"])
  }

  @Test func aRefusedBackupSaysWhyAndWritesNothing() async throws {
    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = FakeBackupSource()
    source.backup = .failure(
      UmbraError(code: "engine_down", message: "The torrent engine isn't running."))
    let model = BackupModel(source: source)
    await model.save(to: folder.appending(path: "b.tar.gz"))
    #expect(model.problem == "The backup wasn't saved. The torrent engine isn't running.")
    #expect(model.status == nil)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
  }

  @Test func restoringNeverGoesAheadWithoutTheConfirmation() async {
    let source = FakeBackupSource()
    let model = BackupModel(source: source)

    // Choosing the file only asks.
    model.askToRestore(file)
    #expect(model.pendingRestore == file)
    #expect(source.restoresAsked.isEmpty)

    // Cancel forgets it; confirming afterwards does nothing.
    model.cancelRestore()
    await model.confirmRestore()
    #expect(source.restoresAsked.isEmpty)
    #expect(model.status == nil)

    // Confirming with nothing chosen does nothing either.
    await model.confirmRestore()
    #expect(source.restoresAsked.isEmpty)

    // Only choosing and then confirming restores, once.
    model.askToRestore(file)
    await model.confirmRestore()
    #expect(source.restoresAsked == [file])
    #expect(model.pendingRestore == nil)
    await model.confirmRestore()
    #expect(source.restoresAsked == [file])
  }

  @Test func aRestoreSaysWhereTheOldDataIs() async {
    let source = FakeBackupSource()
    let model = BackupModel(source: source)
    model.askToRestore(file)
    await model.confirmRestore()
    #expect(
      model.status
        == "Restored from “Umbra backup 2026-11-14 18.40.tar.gz”. The settings and torrent list from before are in /tmp/data/before-restore-2026-11-14-184000."
    )
    #expect(model.problem == nil)
    #expect(model.activity == .idle)
  }

  @Test func aRefusedRestoreSaysWhyAndThatNothingChanged() async {
    let source = FakeBackupSource()
    source.restoreResult = .refused(
      reason: "This backup was made by a newer Umbra (v0.5.0) than this one (v0.3.0).")
    let model = BackupModel(source: source)
    model.askToRestore(file)
    await model.confirmRestore()
    #expect(
      model.problem
        == "The backup wasn't restored, and nothing was changed. This backup was made by a newer Umbra (v0.5.0) than this one (v0.3.0). Umbra started again with the settings it had."
    )
    #expect(model.status == nil)
  }

  @Test func homeIsWrittenAsATilde() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    #expect(
      BackupModel.shortPath(home.appending(path: "Library/Application Support/Umbra"))
        == "~/Library/Application Support/Umbra")
    #expect(BackupModel.shortPath(URL(filePath: "/tmp/x")) == "/tmp/x")
  }
}

/// Reading Umbra's answer to `umbra restore --replace`.
struct HelperRestoreAnswerTests {
  @Test func aRestoreNamesTheKeptFolder() {
    let out = """
      Restored the settings and 3 torrents into /d, from a backup made 14 November 2026 18:40 by Umbra v0.3.0.
      The settings and torrent list from before are kept in /d/before-restore-2026-11-14-184100.
      """
    #expect(
      HelperRestore.result(code: 0, stdout: out, stderr: "", hiding: "tok")
        == .restored(keptIn: "/d/before-restore-2026-11-14-184100"))
    #expect(
      HelperRestore.result(code: 0, stdout: "Restored the settings.\n", stderr: "", hiding: "tok")
        == .restored(keptIn: nil))
  }

  @Test func aRefusalGivesUmbrasReasonWithoutTheToken() {
    #expect(
      HelperRestore.result(
        code: 1, stdout: "",
        stderr: "restore failed: the backup is damaged or cut short: unexpected EOF\n",
        hiding: "tok")
        == .refused(reason: "The backup is damaged or cut short: unexpected EOF."))
    #expect(
      HelperRestore.result(
        code: 1, stdout: "", stderr: "restore failed: secret tok here.", hiding: "tok")
        == .refused(reason: "Secret <hidden> here."))
    #expect(
      HelperRestore.result(code: 2, stdout: "", stderr: "", hiding: "tok")
        == .refused(reason: "Umbra's restore stopped with exit code 2."))
  }
}
