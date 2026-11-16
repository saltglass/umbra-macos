import Foundation

/// How a restore from a backup ended.
public enum BackupRestoreResult: Sendable, Equatable {
  /// Umbra put the backup in place. `keptIn` is the folder holding the
  /// settings and torrent list from before (nil if there were none).
  case restored(keptIn: String?)
  /// Umbra refused it, and nothing was changed. `reason` is Umbra's own
  /// words (a damaged file, one from a newer Umbra, a key that doesn't
  /// match...).
  case refused(reason: String)
}

/// Runs Umbra's own restore: `umbra restore --replace <file>`, a one-off
/// run of the helper program on the same data folder, while the helper
/// itself is stopped. Umbra does all the work and all the checks: it reads
/// the whole file first, refuses a damaged one or one from a newer Umbra,
/// and moves the data from before into a dated folder inside the data
/// folder (`before-restore-<date and time>`) only once the new data is
/// ready. Nothing goes over the network.
///
/// The backup's contents are never read or logged here; only Umbra's short
/// answer (how many torrents, where the old data went, or why it refused).
enum HelperRestore {
  /// The line Umbra prints with the folder the old data was moved to.
  static let keptPrefix = "The settings and torrent list from before are kept in "

  static func run(executable: URL, environment: HelperEnvironment, file: URL) async
    -> BackupRestoreResult
  {
    let token: String
    do {
      // Umbra's settings check needs one with these variables; this run
      // never listens, so the token is never used.
      token = try LaunchToken.make()
    } catch {
      return .refused(reason: error.message)
    }
    let process = Process()
    process.executableURL = executable
    process.arguments = ["restore", "--replace", file.path(percentEncoded: false)]
    process.environment = environment.processEnvironment(
      token: token, inherited: ProcessInfo.processInfo.environment)
    process.currentDirectoryURL = environment.dataFolder
    process.standardInput = FileHandle.nullDevice
    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err

    let ended = AsyncStream.makeStream(of: Int32.self)
    process.terminationHandler = { finished in
      ended.continuation.yield(finished.terminationStatus)
      ended.continuation.finish()
    }
    do {
      try process.run()
    } catch {
      return .refused(
        reason: "Umbra's server program couldn't be started: \(error.localizedDescription)")
    }
    // Read both while it runs, so a full pipe can never hold it up.
    async let stdout = read(out)
    async let stderr = read(err)
    var code: Int32 = -1
    for await status in ended.stream { code = status }
    let said = await stdout
    let problem = await stderr
    return result(code: code, stdout: said, stderr: problem, hiding: token)
  }

  private static func read(_ pipe: Pipe) async -> String {
    let handle = pipe.fileHandleForReading
    let data = await Task.detached { handle.readDataToEndOfFile() }.value
    return String(decoding: data, as: UTF8.self)
  }

  /// What Umbra's answer means. Kept apart from running it, for tests.
  static func result(code: Int32, stdout: String, stderr: String, hiding token: String)
    -> BackupRestoreResult
  {
    func clean(_ text: String) -> String {
      text.replacingOccurrences(of: token, with: "<hidden>")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard code == 0 else {
      var reason = clean(stderr)
      if reason.hasPrefix("restore failed: ") { reason = String(reason.dropFirst(16)) }
      if reason.isEmpty { reason = "Umbra's restore stopped with exit code \(code)." }
      if let first = reason.first { reason = first.uppercased() + reason.dropFirst() }
      if !reason.hasSuffix(".") { reason += "." }
      return .refused(reason: reason)
    }
    let kept = clean(stdout).split(separator: "\n").lazy
      .map(String.init)
      .first { $0.hasPrefix(keptPrefix) }
      .map { line -> String in
        var path = String(line.dropFirst(keptPrefix.count))
        if path.hasSuffix(".") { path.removeLast() }
        return path
      }
    return .restored(keptIn: kept)
  }
}
