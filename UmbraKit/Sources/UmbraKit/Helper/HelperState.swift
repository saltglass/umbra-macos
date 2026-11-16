import Foundation

/// What the bundled helper is doing, for the window to show.
public enum HelperState: Sendable, Equatable {
  /// Not started yet, or stopped on purpose.
  case stopped
  /// Starting for the first time.
  case starting
  /// Up and answering at this connection.
  case running(Connection)
  /// It stopped unexpectedly and is being started again (attempt 1, 2 or 3).
  case restarting(attempt: Int)
  /// Told to stop; waiting while the engine saves.
  case stopping
  /// It couldn't be started, or kept stopping; it won't be tried again
  /// until `start()` is called. `logTail` is the end of helper.log.
  case failed(message: String, logTail: [String])
}

/// A plain-English reason the helper couldn't start, with the end of its log.
///
/// It never holds the launch token: the supervisor removes it from both parts
/// before making one, in case the helper ever printed it.
public struct HelperError: Error, Sendable, Equatable, LocalizedError {
  public let message: String
  public let logTail: [String]

  public init(message: String, logTail: [String]) {
    self.message = message
    self.logTail = logTail
  }

  public var errorDescription: String? { message }

  /// The same error with every copy of `secret` hidden.
  func hiding(_ secret: String) -> HelperError {
    guard !secret.isEmpty else { return self }
    func hide(_ text: String) -> String { text.replacingOccurrences(of: secret, with: "<hidden>") }
    return HelperError(message: hide(message), logTail: logTail.map(hide))
  }
}

/// How the helper ended.
public enum HelperExit: Sendable, Equatable {
  /// It exited by itself with this code (0 is a clean shutdown).
  case exited(code: Int32)
  /// A signal ended it (9 is SIGKILL).
  case killed(signal: Int32)

  public var isClean: Bool { self == .exited(code: 0) }

  var description: String {
    switch self {
    case .exited(let code): "exit code \(code)"
    case .killed(let signal): "ended by signal \(signal)"
    }
  }
}

/// The supervisor's waits and limits. Tests shorten them.
public struct HelperTimings: Sendable {
  /// How long the helper has to write its address and answer /ping.
  public var startTimeout: Duration = .seconds(20)
  /// How often to look for the address file and ping while starting.
  public var pollInterval: Duration = .milliseconds(50)
  /// How long to wait after asking it to stop (the engine saves) before forcing it.
  public var stopGrace: Duration = .seconds(30)
  /// At most this many restarts...
  public var restartLimit = 3
  /// ...within any window this long.
  public var restartWindow: Duration = .seconds(300)
  /// helper.log is moved to helper.log.1 at start when it is bigger than this.
  public var logRotateBytes = 5 * 1024 * 1024
  /// The time now, for counting restarts.
  public var now: @Sendable () -> ContinuousClock.Instant = { .now }

  public init() {}

  public static let standard = HelperTimings()
}
