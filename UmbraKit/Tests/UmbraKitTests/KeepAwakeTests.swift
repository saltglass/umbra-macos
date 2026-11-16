import Foundation
import Testing
import UmbraAPI

@testable import UmbraKit

@Suite struct KeepAwakeTests {
  @Test func everyCombination() {
    for downloading in [false, true] {
      for power in [PowerSource.mains, .battery] {
        for enabled in [false, true] {
          for also in [false, true] {
            let expected: Bool
            if !downloading || !enabled {
              expected = false
            } else {
              expected = power == .mains ? true : also
            }
            #expect(
              KeepAwakePolicy.shouldHold(
                downloading: downloading, power: power, enabled: enabled, alsoOnBattery: also)
                == expected,
              "downloading \(downloading), \(power), switch \(enabled), battery \(also)")
          }
        }
      }
    }
  }

  @Test func onlyActiveDownloadsCount() {
    func with(_ state: Components.Schemas.TorrentState) -> [Components.Schemas.Torrent] {
      var t = row("a")
      t.state = state
      return [t]
    }
    #expect(KeepAwakePolicy.isDownloading(with(.downloading)))
    for state in [
      Components.Schemas.TorrentState.seeding, .paused, .queued, .waitingForVpn,
      .waitingForSpace, .checking, .error, .missingFiles,
    ] {
      #expect(!KeepAwakePolicy.isDownloading(with(state)), "\(state)")
    }
    #expect(!KeepAwakePolicy.isDownloading([]))
  }

  @MainActor @Test func theSwitchesAreRememberedAndHaveTheRightDefaults() {
    let name = "KeepAwakeTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let prefs = KeepAwakePreferences(defaults: defaults)
    #expect(prefs.enabled)
    #expect(!prefs.alsoOnBattery)
    prefs.enabled = false
    prefs.alsoOnBattery = true
    let again = KeepAwakePreferences(defaults: defaults)
    #expect(!again.enabled)
    #expect(again.alsoOnBattery)
  }
}
