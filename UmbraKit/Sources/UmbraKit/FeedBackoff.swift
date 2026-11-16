/// How long to wait before each attempt to reopen a dropped feed.
///
/// 1 second, then 2, 4, 8, 16, then 30 seconds each time after. Waiting longer
/// each time spares a struggling server; the cap keeps the app from looking
/// dead for minutes once the server is back. It starts again at 1 second once
/// a reconnection has really worked (a snapshot arrived).
struct FeedBackoff: Sendable, Equatable {
  static let first: Duration = .seconds(1)
  static let longest: Duration = .seconds(30)

  private var nextWait = Self.first

  /// The wait before the next attempt; each call doubles the one after.
  mutating func next() -> Duration {
    let wait = nextWait
    nextWait = min(nextWait * 2, Self.longest)
    return wait
  }

  /// Back to 1 second.
  mutating func reset() {
    nextWait = Self.first
  }
}
