import Foundation

/// Which screen the main window shows, and the quiet note over the list
/// while the connection to Umbra is down.
public enum SessionScreen {
  /// True when the window should show the list (and not a message in its place).
  ///
  /// While Umbra runs, yes. While it restarts after a crash, or the live
  /// feed drops and retries, the last list received stays on screen (a blank
  /// window would look like data loss) as long as there is one; with none
  /// yet, the centred "Reconnecting…" is shown instead.
  public static func showsList(phase: AppSession.Phase, loaded: Bool) -> Bool {
    switch phase {
    case .running: true
    case .reconnecting: loaded
    case .starting, .saving, .stopped, .failed: false
    }
  }

  /// The words of the small note over the list: "Reconnecting…" while the
  /// helper restarts or the live feed is retrying; nil when all is well.
  /// (Not shown before the first connection, where the list's own spinner is enough.)
  public static func note(phase: AppSession.Phase, connection: FeedConnectionState) -> String? {
    if case .reconnecting = phase { return "Reconnecting…" }
    switch connection {
    case .reconnecting: return "Reconnecting…"
    case .refused: return "Umbra turned the connection away"
    case .connecting, .live: return nil
    }
  }
}
