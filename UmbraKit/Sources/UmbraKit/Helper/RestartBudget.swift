/// Counts restarts, so a helper that keeps crashing isn't restarted forever.
///
/// It allows `limit` restarts within any `window` (3 in 5 minutes for the
/// app). A crash once a day is restarted every time; four crashes in a few
/// minutes means something is really wrong, and restarting again would only
/// hide it.
struct RestartBudget: Sendable {
  let limit: Int
  let window: Duration
  private var restarts: [ContinuousClock.Instant] = []

  init(limit: Int, window: Duration) {
    self.limit = limit
    self.window = window
  }

  /// Asks to restart at `now`. Returns the attempt number (1, 2, 3...) if
  /// allowed, and remembers it; nil if the limit is reached.
  mutating func take(at now: ContinuousClock.Instant) -> Int? {
    restarts.removeAll { now - $0 >= window }
    guard restarts.count < limit else { return nil }
    restarts.append(now)
    return restarts.count
  }

  /// Forgets past restarts (when the person starts it again by hand).
  mutating func reset() { restarts = [] }
}
