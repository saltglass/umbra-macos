import Foundation
import Observation

/// What macOS lets Umbra do about notifications.
public enum NotificationPermission: Sendable, Equatable {
  /// macOS has not been asked yet.
  case notAsked
  case allowed
  /// The person said no (or turned them off in System Settings).
  case refused
}

/// Shows notifications and asks macOS about permission. The real one (in
/// the app) uses macOS's notification centre; tests and pictures use a
/// fake that never does.
@MainActor
public protocol NotificationService: AnyObject {
  func permission() async -> NotificationPermission
  /// Asks macOS (it shows its own question once). True if allowed.
  func requestPermission() async -> Bool
  func deliver(_ notification: PlannedNotification) async
  /// Opens the Notifications pane of System Settings.
  func openSystemSettings()
}

/// Settings → General → "Notifications": the three switches (remembered in
/// the app's own settings, as these are Mac-only) and what macOS allows.
///
/// macOS is asked for permission only when a notification is about to be
/// shown, or when the person turns a switch on. Never at launch.
@MainActor @Observable
public final class NotificationPreferences {
  /// The words under the switches when macOS has said no.
  public static let refusedMessage = "Notifications are turned off for Umbra in System Settings."
  public static let openSettingsButton = "Open System Settings…"

  enum Keys {
    static let finished = "Notifications.finished"
    static let problem = "Notifications.problem"
    static let vpn = "Notifications.vpn"
  }

  public private(set) var switches: NotificationSwitches
  public private(set) var permission: NotificationPermission

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let service: any NotificationService

  /// `permission` is only for pictures: it is what the page shows until `refresh()`.
  public init(
    service: any NotificationService, defaults: UserDefaults = .standard,
    permission: NotificationPermission = .notAsked
  ) {
    self.service = service
    self.defaults = defaults
    self.permission = permission
    switches = NotificationSwitches(
      finished: Self.read(defaults, Keys.finished), problem: Self.read(defaults, Keys.problem),
      vpn: Self.read(defaults, Keys.vpn))
  }

  /// All on until the person says otherwise.
  private static func read(_ defaults: UserDefaults, _ key: String) -> Bool {
    defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
  }

  private func key(_ kind: NotificationKind) -> String {
    switch kind {
    case .finished: Keys.finished
    case .problem: Keys.problem
    case .vpn: Keys.vpn
    }
  }

  public func isOn(_ kind: NotificationKind) -> Bool { switches.isOn(kind) }

  /// True when the page should say macOS has them turned off.
  public var isRefused: Bool { permission == .refused }

  /// Turns one kind on or off. Turning one on asks macOS if it hasn't been asked.
  public func set(_ kind: NotificationKind, on: Bool) async {
    switch kind {
    case .finished: switches.finished = on
    case .problem: switches.problem = on
    case .vpn: switches.vpn = on
    }
    defaults.set(on, forKey: key(kind))
    if on { _ = await ensurePermission() }
  }

  /// Reads macOS's answer again (the page opened, or the app came forward).
  public func refresh() async {
    permission = await service.permission()
  }

  /// True if notifications may be shown, asking macOS first if need be.
  @discardableResult
  public func ensurePermission() async -> Bool {
    await refresh()
    if permission == .notAsked {
      _ = await service.requestPermission()
      await refresh()
    }
    return permission == .allowed
  }

  /// Shows a notification, if its switch is on and macOS allows it.
  public func show(_ notification: PlannedNotification) async {
    guard switches.isOn(notification.kind), await ensurePermission() else { return }
    await service.deliver(notification)
  }

  public func openSystemSettings() { service.openSystemSettings() }
}
