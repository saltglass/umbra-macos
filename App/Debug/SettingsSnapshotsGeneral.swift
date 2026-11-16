#if DEBUG
  import SwiftUI
  import UmbraKit

  /// A stand-in for macOS in pictures of the General page: it says what it
  /// is told and never asks macOS anything.
  @MainActor
  struct FakeDefaultApps: DefaultAppService {
    let apps: [OpeningKind: DefaultAppReading]

    func current(for kind: OpeningKind) -> DefaultAppReading? { apps[kind] }
    func makeDefault(for kind: OpeningKind) async throws {}
  }

  /// A stand-in for macOS's notification centre: shows nothing, asks nothing.
  @MainActor
  final class FakeNotificationService: NotificationService {
    let answer: NotificationPermission
    init(answer: NotificationPermission = .allowed) { self.answer = answer }
    func permission() async -> NotificationPermission { answer }
    func requestPermission() async -> Bool { answer == .allowed }
    func deliver(_ notification: PlannedNotification) async {}
    func openSystemSettings() {}
  }

  /// A stand-in for macOS's login items.
  @MainActor
  struct FakeLoginItem: LoginItemService {
    let current: LoginItemStatus
    func status() -> LoginItemStatus { current }
    func register() throws {}
    func unregister() throws {}
    func openSystemSettings() {}
  }

  /// A stand-in for the app's session in pictures of the Backup section:
  /// makes no backup and restores nothing.
  @MainActor
  final class FakeBackupSource: BackupSource {
    let canUseBackups: Bool
    init(connected: Bool = true) { canUseBackups = connected }
    var backupDataFolder: URL? {
      FileManager.default.homeDirectoryForCurrentUser.appending(
        path: "Library/Application Support/Umbra")
    }
    func makeBackup() async throws(UmbraError) -> Data { Data() }
    func restoreBackup(from file: URL) async -> BackupRestoreResult { .restored(keptIn: nil) }
  }

  /// Pictures of Settings → General. Made-up apps; the switches live in a
  /// throwaway set of defaults, so a picture never changes the real ones.
  @MainActor
  enum SettingsSnapshotsGeneral {
    static let size = CGSize(width: SettingsMetrics.width, height: SettingsMetrics.generalHeight)

    private static func settings(
      apps: [OpeningKind: DefaultAppReading], openingProblems: [OpeningKind: String] = [:],
      permission: NotificationPermission = .allowed, login: LoginItemStatus = .off,
      backup: BackupModel = BackupModel(source: FakeBackupSource())
    ) -> GeneralSettings {
      let defaults = UserDefaults(suiteName: "UmbraSnapshots-General")!
      defaults.removePersistentDomain(forName: "UmbraSnapshots-General")
      return GeneralSettings(
        opening: DefaultAppModel(
          service: FakeDefaultApps(apps: apps), problems: openingProblems),
        notifications: NotificationPreferences(
          service: FakeNotificationService(answer: permission), defaults: defaults,
          permission: permission),
        keepAwake: KeepAwakePreferences(defaults: defaults),
        loginItem: LoginItemModel(service: FakeLoginItem(current: login)),
        backup: backup)
    }

    /// Tall enough to show the whole page, down to the Backup section.
    static let wholePage = CGSize(width: SettingsMetrics.width, height: 880)

    static var entries: [SnapshotEntry] {
      let umbra = DefaultAppReading(name: "Umbra", isUmbra: true)
      let other = DefaultAppReading(name: "qBittorrent", isUmbra: false)
      return [
        // Umbra opens both: the buttons are dimmed. Everything else as it
        // is on first launch.
        SnapshotEntry(name: "settings-general-default", size: size) {
          AnyView(
            GeneralPage(settings: settings(apps: [.torrentFiles: umbra, .magnetLinks: umbra])))
        },
        // Another app opens torrent files; nothing opens magnet links, and
        // macOS has just refused to change that.
        SnapshotEntry(name: "settings-general-not-default", size: size) {
          AnyView(
            GeneralPage(
              settings: settings(
                apps: [.torrentFiles: other],
                openingProblems: [
                  .magnetLinks: "macOS wouldn't change it. The application can't be changed."
                ])))
        },
        // macOS has turned Umbra's notifications off.
        SnapshotEntry(name: "settings-general-notifications-refused", size: size) {
          AnyView(
            GeneralPage(
              settings: settings(
                apps: [.torrentFiles: umbra, .magnetLinks: umbra], permission: .refused)))
        },
        // The login item is registered, but macOS wants the person's approval.
        SnapshotEntry(name: "settings-general-login-approval", size: size) {
          AnyView(
            GeneralPage(
              settings: settings(
                apps: [.torrentFiles: umbra, .magnetLinks: umbra], login: .needsApproval)))
        },
        // The whole page, with the Backup section last, after a backup was saved.
        SnapshotEntry(name: "settings-general-backup", size: wholePage) {
          AnyView(
            GeneralPage(
              settings: settings(
                apps: [.torrentFiles: umbra, .magnetLinks: umbra],
                backup: BackupModel(
                  source: FakeBackupSource(),
                  status: "Saved “Umbra backup 2026-11-14 18.40.tar.gz”."))))
        },
        // A restore Umbra refused (a backup from a newer Umbra).
        SnapshotEntry(name: "settings-general-backup-refused", size: wholePage) {
          AnyView(
            GeneralPage(
              settings: settings(
                apps: [.torrentFiles: umbra, .magnetLinks: umbra],
                backup: BackupModel(
                  source: FakeBackupSource(),
                  problem:
                    "The backup wasn't restored, and nothing was changed. This backup was made by a newer Umbra (v0.5.0) than this one (v0.3.0). Use Umbra v0.5.0 or newer to restore it. Umbra started again with the settings it had."
                ))))
        },
        // Umbra isn't running: both buttons are dimmed.
        SnapshotEntry(name: "settings-general-backup-not-connected", size: wholePage) {
          AnyView(
            GeneralPage(
              settings: settings(
                apps: [.torrentFiles: umbra, .magnetLinks: umbra],
                backup: BackupModel(source: FakeBackupSource(connected: false)))))
        },
      ]
    }
  }
#endif
