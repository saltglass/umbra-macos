import Foundation
import Observation

/// Whether macOS opens Umbra when the person logs in.
public enum LoginItemStatus: Sendable, Equatable {
  case off
  case on
  /// Registered, but the person must allow it in System Settings.
  case needsApproval
  /// macOS can't find the app to register (not in a normal place, say).
  case unavailable
}

/// Reads and changes the login item. The real one (in the app) uses
/// `SMAppService.mainApp`; tests and pictures use a fake.
@MainActor
public protocol LoginItemService {
  func status() -> LoginItemStatus
  func register() throws
  func unregister() throws
  /// Opens System Settings → General → Login Items.
  func openSystemSettings()
}

/// Settings → General → "Startup": the "Open Umbra at login" switch.
@MainActor @Observable
public final class LoginItemModel {
  public static let approvalMessage = "Allow Umbra in System Settings → General → Login Items."
  public static let openSettingsButton = "Open System Settings…"

  private let service: any LoginItemService
  public private(set) var status: LoginItemStatus
  /// What went wrong the last time, in plain words; nil when nothing did.
  public private(set) var problem: String?

  /// `problem` is only for pictures of a failure.
  public init(service: any LoginItemService, problem: String? = nil) {
    self.service = service
    self.problem = problem
    status = service.status()
  }

  /// Reads macOS again (the page opened, or the app came to the front).
  public func refresh() { status = service.status() }

  /// The switch shows on while registered, even if approval is still needed.
  public var isOn: Bool { status == .on || status == .needsApproval }

  public var needsApproval: Bool { status == .needsApproval }

  /// The switch can't work when macOS can't find the app.
  public var canChange: Bool { status != .unavailable }

  /// Words under the row when macOS needs the person's approval, or can't
  /// register the app.
  public var note: String? {
    switch status {
    case .needsApproval: Self.approvalMessage
    case .unavailable: "macOS can't set this up for this copy of Umbra."
    case .off, .on: nil
    }
  }

  /// Turns the login item on or off, then shows what macOS says.
  public func set(_ on: Bool) {
    problem = nil
    do {
      if on { try service.register() } else { try service.unregister() }
    } catch {
      problem = "macOS wouldn't change it. \(error.localizedDescription)"
    }
    refresh()
  }

  public func openSystemSettings() { service.openSystemSettings() }
}
