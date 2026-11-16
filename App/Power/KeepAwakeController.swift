import Foundation
import IOKit.ps
import Observation
import UmbraKit

/// Holds a power assertion while torrents are downloading, so the Mac
/// doesn't fall asleep part way through. The display can still sleep.
/// What to hold is decided by `KeepAwakePolicy` (UmbraKit); this only
/// holds and lets go, and watches for changes.
@MainActor
final class KeepAwakeController {
  private let session: AppSession
  private let preferences: KeepAwakePreferences
  /// The assertion, while held.
  private var activity: (any NSObjectProtocol)?
  private var powerSource: CFRunLoopSource?

  init(session: AppSession, preferences: KeepAwakePreferences) {
    self.session = session
    self.preferences = preferences
  }

  func start() {
    watchPowerSource()
    evaluate()
    watch()
  }

  /// Observation tells once per change, so this signs up again each time.
  private func watch() {
    withObservationTracking {
      _ = session.phase
      _ = session.store.feed
      _ = preferences.enabled
      _ = preferences.alsoOnBattery
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.evaluate()
        self?.watch()
      }
    }
  }

  func evaluate() {
    let connected = session.phase == .running && session.store.isReady
    let downloading = connected && KeepAwakePolicy.isDownloading(session.store.torrents)
    let hold = preferences.shouldHold(downloading: downloading, power: Self.currentPower())
    if hold, activity == nil {
      activity = ProcessInfo.processInfo.beginActivity(
        options: [.idleSystemSleepDisabled], reason: "Downloading torrents")
    } else if !hold, let held = activity {
      ProcessInfo.processInfo.endActivity(held)
      activity = nil
    }
  }

  /// Where the Mac's power comes from right now.
  private static func currentPower() -> PowerSource {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
    else { return .mains }
    return type == kIOPSBatteryPowerValue ? .battery : .mains
  }

  /// Checks again whenever the Mac moves between mains and battery.
  private func watchPowerSource() {
    let context = Unmanaged.passUnretained(self).toOpaque()
    let callback: IOPowerSourceCallbackType = { context in
      guard let context else { return }
      let controller = Unmanaged<KeepAwakeController>.fromOpaque(context).takeUnretainedValue()
      // The source runs on the main run loop, so this is the main thread.
      MainActor.assumeIsolated { controller.evaluate() }
    }
    guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue()
    else { return }
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    powerSource = source
  }
}
