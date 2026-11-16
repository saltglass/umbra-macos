import Foundation
import Synchronization

/// One run of the helper program: started, watched until it ends.
///
/// The supervisor owns these and starts a new one for every restart.
/// Not shared between tasks, so it needs no locking of its own; only the
/// exit watch (which the system calls from its own thread) is shared.
final class HelperProcess {
  let pid: pid_t
  let watch: ExitWatch
  private let process: Process
  /// The app's end of the helper's standard input. It is never written to;
  /// it only has to stay open. When it closes (the app quits or is killed,
  /// and the system closes it), the helper sees "end of input" and shuts
  /// down by itself, so it can never outlive the app.
  private let stdinWriter: FileHandle

  private init(process: Process, stdinWriter: FileHandle, watch: ExitWatch) {
    self.process = process
    self.pid = process.processIdentifier
    self.stdinWriter = stdinWriter
    self.watch = watch
  }

  /// Starts `executable serve` with this environment, its output added to `log`.
  static func launch(
    executable: URL, environment: [String: String], log: HelperLog
  ) throws -> HelperProcess {
    let process = Process()
    process.executableURL = executable
    process.arguments = ["serve"]
    process.environment = environment
    process.currentDirectoryURL = log.url.deletingLastPathComponent()

    let stdin = Pipe()
    process.standardInput = stdin
    let output = try log.openForAppending()
    process.standardOutput = output
    process.standardError = output

    let watch = ExitWatch()
    process.terminationHandler = { finished in
      let exit: HelperExit =
        finished.terminationReason == .uncaughtSignal
        ? .killed(signal: finished.terminationStatus)
        : .exited(code: finished.terminationStatus)
      watch.finish(exit)
    }
    do {
      try process.run()
    } catch {
      try? output.close()
      try? stdin.fileHandleForWriting.close()
      try? stdin.fileHandleForReading.close()
      throw error
    }
    // The helper has its own copies of these now; the app's copies of the
    // log and of the pipe's reading end are no longer needed.
    try? output.close()
    try? stdin.fileHandleForReading.close()
    return HelperProcess(process: process, stdinWriter: stdin.fileHandleForWriting, watch: watch)
  }

  /// Sends a signal (SIGTERM to ask it to stop, SIGKILL to force it),
  /// unless it has already ended: its process number may then belong to
  /// another program.
  func signal(_ signal: Int32) {
    guard watch.exit == nil else { return }
    kill(pid, signal)
  }

  /// Closes the helper's standard input, as the system does when the app ends.
  func closeStdin() {
    try? stdinWriter.close()
  }
}

/// Learns when a process ends and lets any number of tasks wait for it.
final class ExitWatch: Sendable {
  private struct State {
    var exit: HelperExit?
    var waiters: [Int: CheckedContinuation<HelperExit?, Never>] = [:]
    var nextID = 0
  }
  // A Mutex because the system reports the exit from its own thread.
  private let state = Mutex(State())

  /// How it ended, or nil while it is still running.
  var exit: HelperExit? { state.withLock { $0.exit } }

  func finish(_ exit: HelperExit) {
    let waiters = state.withLock { state in
      state.exit = exit
      defer { state.waiters = [:] }
      return Array(state.waiters.values)
    }
    for waiter in waiters { waiter.resume(returning: exit) }
  }

  /// Waits for the end; nil if the waiting task is cancelled first.
  func wait() async -> HelperExit? {
    let id = state.withLock { state in
      state.nextID += 1
      return state.nextID
    }
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let result: HelperExit?? = state.withLock { state in
          if let exit = state.exit { return .some(exit) }
          if Task.isCancelled { return .some(nil) }
          state.waiters[id] = continuation
          return .none
        }
        if case .some(let value) = result { continuation.resume(returning: value) }
      }
    } onCancel: {
      let waiter = state.withLock { $0.waiters.removeValue(forKey: id) }
      waiter?.resume(returning: nil)
    }
  }

  /// Waits for the end for up to `limit`; nil if it is still running then.
  func wait(upTo limit: Duration) async -> HelperExit? {
    if let exit { return exit }
    return await withTaskGroup(of: HelperExit?.self) { group in
      group.addTask { await self.wait() }
      group.addTask {
        try? await Task.sleep(for: limit)
        return nil
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first ?? exit
    }
  }
}
