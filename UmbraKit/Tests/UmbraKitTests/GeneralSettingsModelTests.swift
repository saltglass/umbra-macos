import Foundation
import Testing

@testable import UmbraKit

/// Settings → General: the notification switches and permission, and the
/// login item, over fakes that never ask macOS.
@MainActor @Suite struct GeneralSettingsModelTests {
  final class FakeNotifications: NotificationService {
    var state: NotificationPermission = .notAsked
    /// What macOS answers when asked.
    var answer = true
    private(set) var asked = 0
    private(set) var delivered: [PlannedNotification] = []
    private(set) var openedSettings = false

    func permission() async -> NotificationPermission { state }
    func requestPermission() async -> Bool {
      asked += 1
      state = answer ? .allowed : .refused
      return answer
    }
    func deliver(_ notification: PlannedNotification) async { delivered.append(notification) }
    func openSystemSettings() { openedSettings = true }
  }

  final class FakeLoginItem: LoginItemService {
    struct Failure: LocalizedError { var errorDescription: String? { "Not allowed." } }
    var current: LoginItemStatus = .off
    var failure: (any Error)?
    /// What registering leads to.
    var afterRegister: LoginItemStatus = .on
    private(set) var openedSettings = false
    func status() -> LoginItemStatus { current }
    func register() throws {
      if let failure { throw failure }
      current = afterRegister
    }
    func unregister() throws {
      if let failure { throw failure }
      current = .off
    }
    func openSystemSettings() { openedSettings = true }
  }

  func defaults() -> UserDefaults {
    let defaults = UserDefaults(suiteName: "GeneralSettingsTests-\(UUID().uuidString)")!
    return defaults
  }

  let note = PlannedNotification(kind: .finished, title: "A", body: "Download finished")

  // MARK: Notifications

  @Test func allSwitchesStartOnAndMacOSIsNotAskedAtCreation() {
    let service = FakeNotifications()
    let prefs = NotificationPreferences(service: service, defaults: defaults())
    #expect(prefs.switches == NotificationSwitches())
    #expect(service.asked == 0)
  }

  @Test func macOSIsAskedTheFirstTimeSomethingIsAboutToBeShown() async {
    let service = FakeNotifications()
    let prefs = NotificationPreferences(service: service, defaults: defaults())
    await prefs.show(note)
    #expect(service.asked == 1)
    #expect(service.delivered == [note])
    await prefs.show(note)
    #expect(service.asked == 1)
    #expect(service.delivered.count == 2)
  }

  @Test func nothingIsShownWhenMacOSRefuses() async {
    let service = FakeNotifications()
    service.answer = false
    let prefs = NotificationPreferences(service: service, defaults: defaults())
    await prefs.show(note)
    #expect(service.delivered.isEmpty)
    #expect(prefs.isRefused)
    #expect(
      NotificationPreferences.refusedMessage
        == "Notifications are turned off for Umbra in System Settings.")
  }

  @Test func turningASwitchOnAsksMacOSButOffDoesNot() async {
    let service = FakeNotifications()
    let prefs = NotificationPreferences(service: service, defaults: defaults())
    await prefs.set(.vpn, on: false)
    #expect(service.asked == 0)
    await prefs.set(.vpn, on: true)
    #expect(service.asked == 1)
  }

  @Test func aSwitchThatIsOffShowsNothingAndAsksNothing() async {
    let service = FakeNotifications()
    let prefs = NotificationPreferences(service: service, defaults: defaults())
    await prefs.set(.finished, on: false)
    await prefs.show(note)
    #expect(service.delivered.isEmpty)
    #expect(service.asked == 0)
  }

  @Test func switchesAreRemembered() async {
    let store = defaults()
    let first = NotificationPreferences(service: FakeNotifications(), defaults: store)
    await first.set(.problem, on: false)
    let second = NotificationPreferences(service: FakeNotifications(), defaults: store)
    #expect(second.switches == NotificationSwitches(problem: false))
  }

  @Test func refreshPicksUpAChangeMadeInSystemSettings() async {
    let service = FakeNotifications()
    service.state = .refused
    let prefs = NotificationPreferences(service: service, defaults: defaults())
    await prefs.refresh()
    #expect(prefs.isRefused)
    service.state = .allowed
    await prefs.refresh()
    #expect(!prefs.isRefused)
    prefs.openSystemSettings()
    #expect(service.openedSettings)
  }

  // MARK: Login item

  @Test func loginItemWordsForEachStatus() {
    let service = FakeLoginItem()
    let model = LoginItemModel(service: service)
    #expect(!model.isOn)
    #expect(model.note == nil)
    service.current = .on
    model.refresh()
    #expect(model.isOn)
    #expect(model.note == nil)
    service.current = .needsApproval
    model.refresh()
    #expect(model.isOn)
    #expect(model.needsApproval)
    #expect(model.note == "Allow Umbra in System Settings → General → Login Items.")
    service.current = .unavailable
    model.refresh()
    #expect(!model.canChange)
    #expect(model.note != nil)
  }

  @Test func turningTheLoginItemOnAndOff() {
    let service = FakeLoginItem()
    let model = LoginItemModel(service: service)
    model.set(true)
    #expect(model.isOn)
    model.set(false)
    #expect(!model.isOn)
    #expect(model.problem == nil)
  }

  @Test func registeringCanEndInNeedingApproval() {
    let service = FakeLoginItem()
    service.afterRegister = .needsApproval
    let model = LoginItemModel(service: service)
    model.set(true)
    #expect(model.needsApproval)
    model.openSystemSettings()
    #expect(service.openedSettings)
  }

  @Test func aFailureIsShownInPlainWordsAndClearedOnTheNextTry() {
    let service = FakeLoginItem()
    service.failure = FakeLoginItem.Failure()
    let model = LoginItemModel(service: service)
    model.set(true)
    #expect(model.problem == "macOS wouldn't change it. Not allowed.")
    #expect(!model.isOn)
    service.failure = nil
    model.set(true)
    #expect(model.problem == nil)
    #expect(model.isOn)
  }
}
