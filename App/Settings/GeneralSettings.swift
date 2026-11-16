import UmbraKit

/// Everything Settings → General shows, kept together so the page and the
/// app's own workings (notifications, keeping the Mac awake) share one set
/// of switches. The real ones by default; pictures pass fakes.
@MainActor
struct GeneralSettings {
  let opening: DefaultAppModel
  let notifications: NotificationPreferences
  let keepAwake: KeepAwakePreferences
  let loginItem: LoginItemModel
  let backup: BackupModel

  init(
    opening: DefaultAppModel, notifications: NotificationPreferences,
    keepAwake: KeepAwakePreferences, loginItem: LoginItemModel, backup: BackupModel
  ) {
    self.opening = opening
    self.notifications = notifications
    self.keepAwake = keepAwake
    self.loginItem = loginItem
    self.backup = backup
  }

  /// The real thing: macOS's own services, and backups of the app's own
  /// Umbra (`backupSource` is the app's session).
  init(notificationService: UserNotificationService, backupSource: any BackupSource) {
    opening = DefaultAppModel(service: WorkspaceDefaultApps())
    notifications = NotificationPreferences(service: notificationService)
    keepAwake = KeepAwakePreferences()
    loginItem = LoginItemModel(service: SystemLoginItem())
    backup = BackupModel(source: backupSource)
  }
}
