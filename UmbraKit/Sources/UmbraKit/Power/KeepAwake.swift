import Foundation
import Observation
import UmbraAPI

/// Where the Mac gets its power.
public enum PowerSource: Sendable, Equatable {
  case mains, battery
}

/// Whether the Mac should be kept from sleeping now. Pure: it only
/// answers; the app holds or lets go.
public enum KeepAwakePolicy {
  /// Actively downloading: not paused, queued, held by the VPN or waiting
  /// for disk space, and not only seeding.
  public static func isDownloading(_ torrents: [Components.Schemas.Torrent]) -> Bool {
    torrents.contains { $0.state == .downloading }
  }

  /// Keep awake while downloading, if the switch is on. On battery only if
  /// "Also on battery" is on too.
  public static func shouldHold(
    downloading: Bool, power: PowerSource, enabled: Bool, alsoOnBattery: Bool
  ) -> Bool {
    guard enabled, downloading else { return false }
    switch power {
    case .mains: return true
    case .battery: return alsoOnBattery
    }
  }
}

/// Settings → General → "Power": the two switches, remembered in the app's
/// own settings (they are Mac-only, not Umbra settings).
@MainActor @Observable
public final class KeepAwakePreferences {
  enum Keys {
    static let enabled = "KeepAwake.enabled"
    static let alsoOnBattery = "KeepAwake.alsoOnBattery"
  }

  /// "Keep the Mac awake while downloading". On to begin with.
  public var enabled: Bool {
    didSet { defaults.set(enabled, forKey: Keys.enabled) }
  }
  /// "Also on battery". Off to begin with.
  public var alsoOnBattery: Bool {
    didSet { defaults.set(alsoOnBattery, forKey: Keys.alsoOnBattery) }
  }

  @ObservationIgnored private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    enabled =
      defaults.object(forKey: Keys.enabled) == nil ? true : defaults.bool(forKey: Keys.enabled)
    alsoOnBattery = defaults.bool(forKey: Keys.alsoOnBattery)
  }

  public func shouldHold(downloading: Bool, power: PowerSource) -> Bool {
    KeepAwakePolicy.shouldHold(
      downloading: downloading, power: power, enabled: enabled, alsoOnBattery: alsoOnBattery)
  }
}
