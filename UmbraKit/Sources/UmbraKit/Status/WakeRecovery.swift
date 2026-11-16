import UmbraAPI

/// What the app does when the Mac goes to sleep and wakes up, so the VPN
/// line never shows a "Connected" from before the sleep as if it were true now.
///
/// While the Mac sleeps, Umbra (the helper) is frozen with it. On waking,
/// the last thing it said about the VPN can be hours old, and Umbra itself
/// takes a few seconds to notice that the VPN's session ran out while it
/// slept (the VPN server's clock kept going). Umbra's kill switch keeps
/// everything inside the VPN all the while; this only decides what the
/// person is told meanwhile:
///
/// - From going to sleep until Umbra gives a settled answer after waking,
///   the VPN reads "Checking VPN…" (`isChecking`).
/// - On waking, the live feed is opened afresh (its waits start again at
///   1 second) and Umbra is asked about the VPN at once.
/// - "Connected", "held" and "no VPN" are settled answers. "Down" and
///   "connecting" are not yet: right after waking Umbra is usually making a
///   new session, so it is asked again every few seconds.
/// - After `giveUpAfter` it stops checking and shows whatever Umbra says.
///
/// It only decides; `AppSession` does the asking. Times are passed in, so
/// tests can move them.
public struct WakeRecovery: Sendable, Equatable {
  /// What the caller must do now.
  public enum Step: Sendable, Equatable {
    /// Open the live feed again now, its waits back at the start.
    case reopenFeed
    /// Ask Umbra for the VPN's state now (`GET /vpn?refresh=true`). The
    /// answer is handed back with `answered`, with this round's number.
    case checkVpn(round: Int)
  }

  /// How long after a check that wasn't settled to ask again.
  public static let recheckAfter: Duration = .seconds(4)
  /// How long after waking to stop checking and show Umbra's answer as it is.
  public static let giveUpAfter: Duration = .seconds(20)

  /// True while the VPN should read "Checking VPN…".
  public private(set) var isChecking = false

  /// Set at going to sleep; cleared by waking.
  private var sleptAt: ContinuousClock.Instant?
  private var wokeAt: ContinuousClock.Instant?
  private var lastAsked: ContinuousClock.Instant?
  /// A check is out and its answer hasn't come back.
  private var asking = false
  /// Umbra gave a settled answer; waiting only for the live feed to be open.
  private var settled = false
  /// Goes up at every sleep, so an answer to a check from before it is ignored.
  private var round = 0

  public init() {}

  /// Between going to sleep and waking.
  public var isAsleep: Bool { sleptAt != nil }

  /// The Mac is about to sleep. `connected`: the app is connected to Umbra.
  public mutating func willSleep(at now: ContinuousClock.Instant, connected: Bool) {
    round += 1
    asking = false
    settled = false
    wokeAt = nil
    sleptAt = now
    // Set now, so the first thing on screen after waking is already right,
    // even before the wake notice arrives.
    isChecking = connected
  }

  /// The Mac woke up. Nothing happens unless the app is connected to Umbra
  /// (a helper that is starting or restarting gets fresh answers anyway).
  /// A second wake while a check is still out adds no work.
  public mutating func didWake(at now: ContinuousClock.Instant, connected: Bool) -> [Step] {
    sleptAt = nil
    guard connected else {
      isChecking = false
      return []
    }
    let first = wokeAt == nil
    if first {
      wokeAt = now
      settled = false
    }
    isChecking = true
    var steps: [Step] = first ? [.reopenFeed] : []
    if !asking {
      asking = true
      lastAsked = now
      steps.append(.checkVpn(round: round))
    }
    return steps
  }

  /// Umbra answered a check: `state` is what it said (nil if the check
  /// failed), `feedLive` whether the live feed is open again.
  public mutating func answered(
    _ state: Components.Schemas.VpnState?, round answered: Int, feedLive: Bool,
    at now: ContinuousClock.Instant
  ) {
    guard answered == round, asking else { return }  // from before a later sleep
    asking = false
    switch state {
    case .some(.connected), .some(.held), .some(.none):
      settled = true
      // The feed carries the state from now on; until it is open again,
      // the window couldn't show the answer anyway (see `tick`).
      if feedLive { isChecking = false }
    case .some(.connecting), .some(.down), nil:
      break  // asked again by `tick`
    }
  }

  /// Called every second or so while `isChecking`: asks again when it is
  /// time, and gives up after `giveUpAfter`. A wake notice that never came
  /// is made up for here: a "sleep" that has lasted longer than
  /// `giveUpAfter` counts as woken (the clock keeps going during sleep).
  /// `feedLive`: the live feed is open again.
  public mutating func tick(
    at now: ContinuousClock.Instant, connected: Bool, feedLive: Bool
  ) -> [Step] {
    if let sleptAt, now - sleptAt >= Self.giveUpAfter {
      return didWake(at: now, connected: connected)
    }
    guard isChecking, let wokeAt else { return [] }
    if !connected || now - wokeAt >= Self.giveUpAfter || (settled && feedLive) {
      isChecking = false
      asking = false
      return []
    }
    guard !settled, !asking, let lastAsked, now - lastAsked >= Self.recheckAfter else { return [] }
    asking = true
    self.lastAsked = now
    return [.checkVpn(round: round)]
  }
}
