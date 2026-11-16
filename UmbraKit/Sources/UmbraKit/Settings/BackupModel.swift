import Foundation
import Observation

/// Where backups come from and go to: the app's session in the real app
/// (`AppSession`), a fake in tests and pictures.
@MainActor
public protocol BackupSource: AnyObject {
  /// True while connected to Umbra's own helper (not while it starts,
  /// stops or restores, and never for a development server).
  var canUseBackups: Bool { get }
  /// The helper's data folder, where the data from before a restore is kept.
  var backupDataFolder: URL? { get }
  /// A backup as Umbra made it.
  func makeBackup() async throws(UmbraError) -> Data
  /// Stops the helper, has Umbra restore the file, starts the helper again.
  func restoreBackup(from file: URL) async -> BackupRestoreResult
}

/// Settings → General → "Backup": saving a backup to a file, and restoring
/// from one.
///
/// Restoring replaces this Mac's Umbra settings, torrent list and saved
/// VPNs, so it takes two steps: `askToRestore` only notes the file (the
/// page then shows a warning), and only `confirmRestore`, the warning's
/// own button, goes ahead. Umbra does the restore itself and keeps the old
/// data aside (see `HelperRestore`).
@MainActor @Observable
public final class BackupModel {
  public static let saveButton = "Save a Backup…"
  public static let restoreButton = "Restore from Backup…"
  /// What a backup holds, in one line.
  public static let contents =
    "A backup holds Umbra's settings, the torrent list and the saved VPNs. It doesn't hold the downloaded files themselves."
  public static let keepPrivate =
    "Keep it private: it holds your saved VPNs. Only Umbra on this Mac can restore it, as the VPNs in it are locked with a key kept on this Mac."
  public static let alertTitle = "Replace Umbra's settings and torrent list with the backup's?"
  public static let alertCancel = "Cancel"
  public static let alertConfirm = "Replace"

  private let source: any BackupSource
  /// What is happening now.
  public private(set) var activity: Activity = .idle
  /// What happened the last time, in plain words; nil before anything has.
  public private(set) var status: String?
  /// What went wrong the last time, in plain words; nil when nothing did.
  public private(set) var problem: String?
  /// The file chosen to restore from, waiting for the person to confirm.
  public private(set) var pendingRestore: URL?

  public enum Activity: Sendable, Equatable {
    case idle, saving, restoring
  }

  /// `status` and `problem` are only for pictures.
  public init(source: any BackupSource, status: String? = nil, problem: String? = nil) {
    self.source = source
    self.status = status
    self.problem = problem
  }

  /// The buttons work only while connected to Umbra and nothing else is
  /// under way.
  public var isEnabled: Bool { source.canUseBackups && activity == .idle }

  /// The words beside the buttons while one is at work.
  public var activityText: String? {
    switch activity {
    case .idle: nil
    case .saving: "Saving the backup…"
    case .restoring: "Restoring… Umbra is starting again."
    }
  }

  /// The name the save panel suggests, such as
  /// "Umbra backup 2026-11-14 18.40.tar.gz" (Umbra's backups are .tar.gz
  /// files).
  public static func suggestedFileName(at date: Date, timeZone: TimeZone = .current) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    let text = String(
      format: "%04d-%02d-%02d %02d.%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0,
      c.minute ?? 0)
    return "Umbra backup \(text).tar.gz"
  }

  // MARK: Saving

  /// Asks Umbra for a backup and writes it to `file` (chosen in the save
  /// panel), readable by this user only.
  public func save(to file: URL) async {
    guard isEnabled else { return }
    activity = .saving
    problem = nil
    status = nil
    defer { activity = .idle }
    do {
      let data = try await source.makeBackup()
      try BackupFile.write(data, to: file)
      status = "Saved “\(file.lastPathComponent)”."
    } catch let error as UmbraError {
      problem = "The backup wasn't saved. \(error.message)"
    } catch {
      problem = "The backup wasn't saved. \(error.localizedDescription)"
    }
  }

  // MARK: Restoring

  /// Notes the file chosen in the open panel. Nothing is restored until
  /// `confirmRestore`.
  public func askToRestore(_ file: URL) {
    guard isEnabled else { return }
    pendingRestore = file
  }

  /// The warning's Cancel.
  public func cancelRestore() { pendingRestore = nil }

  /// The warning's text for the chosen file.
  public var alertMessage: String {
    let name = pendingRestore?.lastPathComponent ?? "the backup"
    var location = "inside Umbra's data folder"
    if let folder = source.backupDataFolder {
      location += " (\(Self.shortPath(folder)))"
    }
    return
      "This Mac's Umbra settings, torrent list and saved VPNs will be replaced by the ones in “\(name)”. "
      + "Downloaded files aren't touched.\n\n"
      + "The current settings and torrent list are kept in a folder named “before-restore-” "
      + "and today's date and time, \(location).\n\n"
      + "Umbra stops while it restores, then starts again."
  }

  /// The warning's Replace: restores the file chosen, if there is one.
  /// Without a chosen file it does nothing.
  public func confirmRestore() async {
    guard let file = pendingRestore else { return }
    pendingRestore = nil
    guard source.canUseBackups, activity == .idle else { return }
    activity = .restoring
    problem = nil
    status = nil
    let result = await source.restoreBackup(from: file)
    activity = .idle
    switch result {
    case .restored(let kept):
      var text = "Restored from “\(file.lastPathComponent)”."
      if let kept {
        text +=
          " The settings and torrent list from before are in \(Self.shortPath(URL(filePath: kept)))."
      }
      status = text
    case .refused(let reason):
      problem =
        "The backup wasn't restored, and nothing was changed. \(reason) Umbra started again with the settings it had."
    }
  }

  /// A path with the home folder written as "~".
  static func shortPath(_ url: URL) -> String {
    let path = url.path(percentEncoded: false)
    let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
    let trimmedHome = home.hasSuffix("/") ? String(home.dropLast()) : home
    guard !trimmedHome.isEmpty, path.hasPrefix(trimmedHome + "/") else { return path }
    return "~" + path.dropFirst(trimmedHome.count)
  }
}

/// Writes a backup to the file the person chose. A backup is secret (it
/// holds the saved VPNs), so the file is readable and writable by this user
/// only (permissions 0600), and is never left half-written: it is written
/// beside the destination under a hidden name first, then moved into place.
public enum BackupFile {
  public static func write(_ data: Data, to file: URL) throws {
    let folder = file.deletingLastPathComponent()
    let partial = folder.appending(
      path: ".\(file.lastPathComponent).\(UUID().uuidString).partial", directoryHint: .notDirectory)
    let partialPath = partial.path(percentEncoded: false)
    let fd = open(partialPath, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
    guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    var failure: POSIXErrorCode?
    if fchmod(fd, 0o600) != 0 { failure = POSIXErrorCode(rawValue: errno) ?? .EIO }
    if failure == nil {
      data.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
          let written = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
          if written < 0 {
            if errno == EINTR { continue }
            failure = POSIXErrorCode(rawValue: errno) ?? .EIO
            return
          }
          offset += written
        }
      }
    }
    if failure == nil, fsync(fd) != 0 { failure = POSIXErrorCode(rawValue: errno) ?? .EIO }
    close(fd)
    if failure == nil, rename(partialPath, file.path(percentEncoded: false)) != 0 {
      failure = POSIXErrorCode(rawValue: errno) ?? .EIO
    }
    if let failure {
      unlink(partialPath)
      throw POSIXError(failure)
    }
  }
}
