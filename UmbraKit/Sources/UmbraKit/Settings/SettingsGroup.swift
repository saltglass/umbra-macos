import Foundation
import UmbraAPI

/// One of Umbra's settings groups, as a settings page edits it: its name
/// (the one Umbra's live feed uses when it says the group changed), and
/// how to read it and replace it.
///
/// `Value` is what the page edits. For most groups it is simply the group
/// as Umbra sends it. For a group holding a secret (the mail password) it
/// also carries what to do with the secret, which Umbra never sends back
/// (see `NotificationsDraft`).
///
/// To add a group: add a `static var` in an extension below, naming the
/// two `SettingsActions` calls.
public struct SettingsGroup<Value: Equatable & Sendable>: Sendable {
  /// Umbra's name for the group: "queue", "seeding"...
  public let name: String
  let read: @Sendable (SettingsActions) async throws(UmbraError) -> Value
  let write: @Sendable (Value, SettingsActions) async throws(UmbraError) -> Value

  public init(
    name: String,
    read: @escaping @Sendable (SettingsActions) async throws(UmbraError) -> Value,
    write: @escaping @Sendable (Value, SettingsActions) async throws(UmbraError) -> Value
  ) {
    self.name = name
    self.read = read
    self.write = write
  }
}

extension SettingsGroup where Value == Components.Schemas.DownloadsSettings {
  /// Settings → Downloads: folders, categories, space kept free.
  public static var downloads: Self {
    Self(
      name: "downloads",
      read: { actions async throws(UmbraError) in try await actions.downloads() },
      write: { value, actions async throws(UmbraError) in try await actions.setDownloads(value) })
  }
}

extension SettingsGroup where Value == Components.Schemas.SpeedSettings {
  /// Settings → Speed: limits, slow mode and its schedule.
  public static var speed: Self {
    Self(
      name: "speed", read: { actions async throws(UmbraError) in try await actions.speed() },
      write: { value, actions async throws(UmbraError) in try await actions.setSpeed(value) })
  }
}

extension SettingsGroup where Value == Components.Schemas.QueueSettings {
  /// Settings → Queue: how many torrents run at once.
  public static var queue: Self {
    Self(
      name: "queue", read: { actions async throws(UmbraError) in try await actions.queue() },
      write: { value, actions async throws(UmbraError) in try await actions.setQueue(value) })
  }
}

extension SettingsGroup where Value == Components.Schemas.SeedingSettings {
  /// Settings → Seeding: the seed goals.
  public static var seeding: Self {
    Self(
      name: "seeding", read: { actions async throws(UmbraError) in try await actions.seeding() },
      write: { value, actions async throws(UmbraError) in try await actions.setSeeding(value) })
  }
}

extension SettingsGroup where Value == Components.Schemas.ConnectionSettings {
  /// Settings → Connection: the peer port, the DHT and peer exchange.
  public static var connection: Self {
    Self(
      name: "connection",
      read: { actions async throws(UmbraError) in try await actions.connection() },
      write: { value, actions async throws(UmbraError) in try await actions.setConnection(value) })
  }
}

extension SettingsGroup where Value == NotificationsDraft {
  /// Settings → Notifications: email. The password travels only as a
  /// change (see `NotificationsDraft`).
  public static var notifications: Self {
    Self(
      name: "notifications",
      read: { actions async throws(UmbraError) in
        NotificationsDraft(try await actions.notifications())
      },
      write: { draft, actions async throws(UmbraError) in
        NotificationsDraft(try await actions.setNotifications(draft.update))
      })
  }
}

// MARK: Secrets

/// What to do with a secret Umbra keeps but never sends back (the mail
/// password): leave it, replace it, or remove it.
///
/// It never shows the secret in text: printing, logging or `dump`ing one
/// gives only which of the three it is.
public enum SecretChange: Equatable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible, CustomReflectable
{
  /// Keep whatever Umbra has stored (nothing is sent).
  case unchanged
  /// Store this one instead.
  case replaced(String)
  /// Remove the stored one.
  case removed

  /// What Umbra's API takes: left out keeps the stored one, "" removes it.
  var wire: String? {
    switch self {
    case .unchanged: nil
    case .replaced(let secret): secret
    case .removed: ""
    }
  }

  public var description: String {
    switch self {
    case .unchanged: "unchanged"
    case .replaced: "replaced (hidden)"
    case .removed: "removed"
    }
  }
  public var debugDescription: String { description }
  public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Settings → Notifications as its page edits it: the settings Umbra sent,
/// plus what to do with the password. After every save Umbra's answer
/// comes back with `password` as `.unchanged`, so a typed password lives
/// only until it is sent. Nothing here is ever written to disk.
public struct NotificationsDraft: Equatable, Sendable {
  public var settings: Components.Schemas.NotificationsSettings
  public var password: SecretChange

  public init(
    _ settings: Components.Schemas.NotificationsSettings, password: SecretChange = .unchanged
  ) {
    self.settings = settings
    self.password = password
  }

  /// The body of the replace request.
  var update: Components.Schemas.NotificationsSettingsUpdate {
    let s = settings
    return .init(
      enabled: s.enabled, host: s.host, port: s.port,
      security: .init(rawValue: s.security.rawValue) ?? .starttls, username: s.username,
      password: password.wire, from: s.from, to: s.to, onFinished: s.onFinished,
      onError: s.onError, onVpn: s.onVpn, onLowDisk: s.onLowDisk)
  }
}
