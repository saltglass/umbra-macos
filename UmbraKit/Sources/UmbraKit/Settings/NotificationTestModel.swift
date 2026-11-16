import Foundation
import Observation

/// The "Send a Test" button on Settings → Notifications: one test email,
/// and what came of it, for the page to show next to the button.
///
/// The settings (and a password typed but not yet sent) go to Umbra as
/// they are; nothing is saved by it. The answer is Umbra's own: "sent", or
/// its explanation of why the mail server refused or couldn't be reached.
/// This never contacts a mail server itself; Umbra does.
@MainActor @Observable
public final class NotificationTestModel {
  public enum State: Equatable, Sendable {
    /// Nothing has been tried (or the settings changed since).
    case idle
    /// Waiting for the mail server's answer; this can take a while.
    case sending
    /// The mail server took the email.
    case sent
    /// It didn't work; `message` is Umbra's explanation, in plain words.
    case failed(message: String)
  }

  public private(set) var state: State

  public init() {
    state = .idle
  }

  /// A model showing a fixed state (pictures of the page and previews).
  public init(fixture state: State) {
    self.state = state
  }

  /// True while a test is on its way: the button waits.
  public var isSending: Bool { state == .sending }

  /// Sends the test with `actions` (nil while not connected). Does
  /// nothing if one is already on its way.
  public func send(_ draft: NotificationsDraft, using actions: SettingsActions?) {
    guard !isSending else { return }
    guard let actions else {
      state = .failed(message: "Umbra isn't running, so a test can't be sent.")
      return
    }
    state = .sending
    Task {
      let outcome: State
      do throws(UmbraError) {
        try await actions.testNotifications(draft)
        outcome = .sent
      } catch {
        outcome = .failed(message: Self.explanation(for: error))
      }
      state = outcome
    }
  }

  /// Forgets the last result (the settings changed, so it no longer
  /// says anything about them). A test still on its way is left alone.
  public func clear() {
    if !isSending { state = .idle }
  }

  /// Umbra's words for a refusal. When it names the settings at fault, those
  /// say more than its general line ("Some fields need attention.").
  static func explanation(for error: UmbraError) -> String {
    let named = error.fields.sorted { $0.key < $1.key }.map(\.value)
    return named.isEmpty ? error.message : named.joined(separator: " ")
  }
}
