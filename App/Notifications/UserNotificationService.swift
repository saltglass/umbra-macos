import AppKit
import UmbraKit
import UserNotifications

/// The real `NotificationService`: macOS's notification centre. Pictures of
/// the views and the tests never use this one.
///
/// It also answers macOS when a notification arrives while Umbra is the
/// front app (still shown) and when the person clicks one.
@MainActor
final class UserNotificationService: NSObject, NotificationService,
  UNUserNotificationCenterDelegate
{
  private nonisolated static let hashKey = "torrentHash"
  private static let settingsURL = URL(
    string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!

  /// Called when a notification is clicked. The hash is the torrent's, or
  /// nil for the VPN and for summaries.
  var onClick: @MainActor (String?) -> Void = { _ in }

  private var center: UNUserNotificationCenter { .current() }

  /// Starts answering macOS. Doesn't ask for permission.
  func attach() {
    center.delegate = self
  }

  func permission() async -> NotificationPermission {
    let status = await center.notificationSettings().authorizationStatus
    switch status {
    case .notDetermined: return .notAsked
    case .denied: return .refused
    default: return .allowed
    }
  }

  func requestPermission() async -> Bool {
    (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
  }

  func deliver(_ notification: PlannedNotification) async {
    let content = UNMutableNotificationContent()
    content.title = notification.title
    content.body = notification.body
    if let hash = notification.torrentHash { content.userInfo = [Self.hashKey: hash] }
    let request = UNNotificationRequest(
      identifier: UUID().uuidString, content: content, trigger: nil)
    try? await center.add(request)
  }

  func openSystemSettings() {
    NSWorkspace.shared.open(Self.settingsURL)
  }

  // MARK: What macOS asks of the delegate

  /// Shown even while Umbra is the front app.
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list]
  }

  /// A click: bring the window forward and select the torrent.
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    let hash = response.notification.request.content.userInfo[Self.hashKey] as? String
    await MainActor.run { onClick(hash) }
  }
}
