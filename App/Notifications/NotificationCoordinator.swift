import Foundation
import Observation
import UmbraKit

/// Feeds what the app knows to the planner (UmbraKit) each time it changes,
/// and shows what the planner says to show. It decides nothing itself.
@MainActor
final class NotificationCoordinator {
  private let session: AppSession
  private let preferences: NotificationPreferences
  private var planner = NotificationPlanner()
  private let now: () -> Date

  init(
    session: AppSession, preferences: NotificationPreferences,
    now: @escaping () -> Date = { Date() }
  ) {
    self.session = session
    self.preferences = preferences
    self.now = now
  }

  /// Starts following the torrent list. Safe to call once.
  func start() {
    evaluate()
    watch()
  }

  /// Observation tells once per change, so this signs up again each time.
  private func watch() {
    withObservationTracking {
      _ = session.phase
      _ = session.store.feed
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.evaluate()
        self?.watch()
      }
    }
  }

  private func evaluate() {
    let store = session.store
    let snapshot = NotificationSnapshot(
      torrents: store.torrents, transfer: store.transfer,
      connected: session.phase == .running && store.isReady, now: now())
    let planned = planner.plan(snapshot, switches: preferences.switches)
    guard !planned.isEmpty else { return }
    let preferences = preferences
    Task {
      for notification in planned { await preferences.show(notification) }
    }
  }
}
