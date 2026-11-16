import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import UmbraAPI

/// Reading and replacing Umbra's settings groups, one request each.
///
/// Every replace sends the whole group (Umbra's API works that way) and
/// returns what Umbra stored, which can differ a little from what was sent
/// (Umbra tidies folder paths, for example). A refusal throws an
/// `UmbraError` carrying Umbra's own words: `message` for the page, and
/// `fields` naming each field that needs attention.
///
/// Nothing is checked here: Umbra decides what is allowed.
public struct SettingsActions: Sendable {
  private let client: Client

  public init(connection: Connection) {
    self.init(connection: connection, transport: URLSessionTransport())
  }

  /// Same, over a transport of the caller's choosing (tests use a fake one).
  public init(connection: Connection, transport: any ClientTransport) {
    client = connection.makeClient(
      transport: transport, extraMiddlewares: [ServerErrorMiddleware()])
  }

  // MARK: Downloads

  public func downloads() async throws(UmbraError) -> Components.Schemas.DownloadsSettings {
    let output = try await callUmbra { try await client.getDownloadsSettings() }
    guard case .ok(let ok) = output, case .json(let value) = ok.body else {
      throw .unexpectedAnswer
    }
    return value
  }

  public func setDownloads(
    _ value: Components.Schemas.DownloadsSettings
  ) async throws(UmbraError) -> Components.Schemas.DownloadsSettings {
    let output = try await callUmbra { try await client.putDownloadsSettings(body: .json(value)) }
    guard case .ok(let ok) = output, case .json(let stored) = ok.body else {
      throw .unexpectedAnswer
    }
    return stored
  }

  // MARK: Speed

  public func speed() async throws(UmbraError) -> Components.Schemas.SpeedSettings {
    let output = try await callUmbra { try await client.getSpeedSettings() }
    guard case .ok(let ok) = output, case .json(let value) = ok.body else {
      throw .unexpectedAnswer
    }
    return value
  }

  public func setSpeed(
    _ value: Components.Schemas.SpeedSettings
  ) async throws(UmbraError) -> Components.Schemas.SpeedSettings {
    let output = try await callUmbra { try await client.putSpeedSettings(body: .json(value)) }
    guard case .ok(let ok) = output, case .json(let stored) = ok.body else {
      throw .unexpectedAnswer
    }
    return stored
  }

  // MARK: Seeding

  public func seeding() async throws(UmbraError) -> Components.Schemas.SeedingSettings {
    let output = try await callUmbra { try await client.getSeedingSettings() }
    guard case .ok(let ok) = output, case .json(let value) = ok.body else {
      throw .unexpectedAnswer
    }
    return value
  }

  public func setSeeding(
    _ value: Components.Schemas.SeedingSettings
  ) async throws(UmbraError) -> Components.Schemas.SeedingSettings {
    let output = try await callUmbra { try await client.putSeedingSettings(body: .json(value)) }
    guard case .ok(let ok) = output, case .json(let stored) = ok.body else {
      throw .unexpectedAnswer
    }
    return stored
  }

  // MARK: Queue

  public func queue() async throws(UmbraError) -> Components.Schemas.QueueSettings {
    let output = try await callUmbra { try await client.getQueueSettings() }
    guard case .ok(let ok) = output, case .json(let value) = ok.body else {
      throw .unexpectedAnswer
    }
    return value
  }

  public func setQueue(
    _ value: Components.Schemas.QueueSettings
  ) async throws(UmbraError) -> Components.Schemas.QueueSettings {
    let output = try await callUmbra { try await client.putQueueSettings(body: .json(value)) }
    guard case .ok(let ok) = output, case .json(let stored) = ok.body else {
      throw .unexpectedAnswer
    }
    return stored
  }

  // MARK: Connection

  public func connection() async throws(UmbraError) -> Components.Schemas.ConnectionSettings {
    let output = try await callUmbra { try await client.getConnectionSettings() }
    guard case .ok(let ok) = output, case .json(let value) = ok.body else {
      throw .unexpectedAnswer
    }
    return value
  }

  public func setConnection(
    _ value: Components.Schemas.ConnectionSettings
  ) async throws(UmbraError) -> Components.Schemas.ConnectionSettings {
    let output = try await callUmbra { try await client.putConnectionSettings(body: .json(value)) }
    guard case .ok(let ok) = output, case .json(let stored) = ok.body else {
      throw .unexpectedAnswer
    }
    return stored
  }

  // MARK: Notifications

  /// The email settings. The mail password is never sent back: only
  /// `passwordSet` says whether one is stored.
  public func notifications() async throws(UmbraError) -> Components.Schemas.NotificationsSettings {
    let output = try await callUmbra { try await client.getNotificationsSettings() }
    guard case .ok(let ok) = output, case .json(let value) = ok.body else {
      throw .unexpectedAnswer
    }
    return value
  }

  /// Replaces the email settings. In `value`, a `password` left out keeps
  /// the stored one and "" removes it (see `SecretChange`).
  public func setNotifications(
    _ value: Components.Schemas.NotificationsSettingsUpdate
  ) async throws(UmbraError) -> Components.Schemas.NotificationsSettings {
    let output = try await callUmbra {
      try await client.putNotificationsSettings(body: .json(value))
    }
    guard case .ok(let ok) = output, case .json(let stored) = ok.body else {
      throw .unexpectedAnswer
    }
    return stored
  }

  // MARK: - Test email (Settings → Notifications, "Send a Test")

  /// Asks Umbra to send one test email with these settings, whether they
  /// are saved or not, and waits for the mail server's answer. Nothing is
  /// saved. In `draft`, a password left `.unchanged` makes Umbra use the
  /// stored one.
  ///
  /// Success is silence. If the mail server can't be reached or says no,
  /// the `UmbraError` carries Umbra's own explanation of why; a setting
  /// Umbra won't accept is named in its `fields`.
  public func testNotifications(_ draft: NotificationsDraft) async throws(UmbraError) {
    let output = try await callUmbra {
      try await client.testNotifications(body: .json(draft.update))
    }
    guard case .noContent = output else { throw .unexpectedAnswer }
  }

  // MARK: - VPN (Settings → VPN, the pill and the banners)
  //
  // The VPN isn't one of the settings groups: it has operations of its own.
  // Umbra decides everything here (the kill switch, holding, releasing);
  // these only ask. A WireGuard configuration holds a private key, so it
  // travels as a `VpnConfiguration`, which never shows its text, and is
  // handed straight to the request: nothing here keeps or logs it.

  /// The VPN's state, the saved VPNs and switching. With `refresh`, Umbra
  /// looks up the addresses now (at most once in 30 seconds).
  public func vpn(refresh: Bool = false) async throws(UmbraError) -> Components.Schemas.VpnStatus {
    let output = try await callUmbra {
      try await client.getVpn(query: .init(refresh: refresh ? true : nil))
    }
    guard case .ok(let ok) = output, case .json(let status) = ok.body else {
      throw .unexpectedAnswer
    }
    return status
  }

  /// Saves a WireGuard configuration. Umbra reads and checks it, and
  /// refuses it (with its reason under `fields["config"]` or `message`)
  /// if it can't be used. The first VPN saved goes in use at once.
  public func addVpn(
    _ configuration: VpnConfiguration, name: String? = nil
  ) async throws(UmbraError) -> Components.Schemas.VpnProfile {
    let output = try await callUmbra {
      try await client.addVpn(
        body: .json(.init(config: configuration.text, name: name)))
    }
    guard case .created(let created) = output, case .json(let profile) = created.body else {
      throw .unexpectedAnswer
    }
    return profile
  }

  /// Renames a saved VPN, sets its forwarded port (0 is none), or replaces
  /// its file. Anything left nil stays as it is.
  public func editVpn(
    id: String, name: String? = nil, forwardedPort: Int? = nil,
    configuration: VpnConfiguration? = nil
  ) async throws(UmbraError) {
    let output = try await callUmbra {
      try await client.editVpn(
        path: .init(id: id),
        body: .json(
          .init(name: name, config: configuration?.text, forwardedPort: forwardedPort)))
    }
    guard case .noContent = output else { throw .unexpectedAnswer }
  }

  /// Removes a saved VPN. Removing the last one holds every torrent.
  public func removeVpn(id: String) async throws(UmbraError) {
    let output = try await callUmbra { try await client.removeVpn(path: .init(id: id)) }
    guard case .noContent = output else { throw .unexpectedAnswer }
  }

  /// Puts a saved VPN in use (every torrent pauses for a few seconds).
  public func useVpn(id: String) async throws(UmbraError) {
    let output = try await callUmbra { try await client.useVpn(path: .init(id: id)) }
    guard case .noContent = output else { throw .unexpectedAnswer }
  }

  /// The order switching tries the saved VPNs in: every id, once each.
  public func orderVpns(_ ids: [String]) async throws(UmbraError) {
    let output = try await callUmbra { try await client.orderVpns(body: .json(.init(ids: ids))) }
    guard case .noContent = output else { throw .unexpectedAnswer }
  }

  /// Switching to the next saved VPN after the one in use has been down
  /// for `minutes`.
  public func setVpnFailover(enabled: Bool, minutes: Int) async throws(UmbraError) {
    let output = try await callUmbra {
      try await client.putVpnFailover(body: .json(.init(enabled: enabled, minutes: minutes)))
    }
    guard case .noContent = output else { throw .unexpectedAnswer }
  }

  /// Asks Umbra to run without a VPN, releasing its hold; peers then see
  /// this Mac's real address. Only ever called after the person has
  /// confirmed it (see `StartWithoutVpnConfirmation`).
  public func startWithoutVpn() async throws(UmbraError) {
    let output = try await callUmbra { try await client.startWithoutVpn() }
    guard case .noContent = output else { throw .unexpectedAnswer }
  }

  // MARK: Backup

  /// The most of a backup that is read. A backup is a few MB for most
  /// libraries; this only stops a runaway answer filling the memory.
  static let backupLimit = 1 << 30

  /// A backup of this Umbra (its settings, torrent list and saved VPNs), as
  /// Umbra made it, ready to save to a file. It is secret: it holds the
  /// saved VPNs, so it is never logged or kept anywhere but that file.
  public func backup() async throws(UmbraError) -> Data {
    let output = try await callUmbra { try await client.downloadBackup() }
    guard case .ok(let ok) = output, case .application_gzip(let body) = ok.body else {
      throw .unexpectedAnswer
    }
    do {
      return try await Data(collecting: body, upTo: Self.backupLimit)
    } catch {
      throw .unreachable(error)
    }
  }
}

/// A WireGuard configuration on its way to Umbra. It holds a private key,
/// so it never shows its text: printing, logging or `dump`ing one gives
/// only "VPN configuration (hidden)". Nothing makes one but reading a file
/// the person chose or text they pasted, and it is dropped once sent.
public struct VpnConfiguration: Equatable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible, CustomReflectable
{
  /// Only for the request body.
  let text: String

  public init(_ text: String) {
    self.text = text
  }

  /// Whether there is anything in it but spaces (an empty one isn't sent).
  public var isBlank: Bool { text.allSatisfy(\.isWhitespace) }

  public var description: String { "VPN configuration (hidden)" }
  public var debugDescription: String { description }
  public var customMirror: Mirror { Mirror(self, children: [:]) }
}
