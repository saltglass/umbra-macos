import Foundation
import Observation

/// What the menu bar item needs from the app: its summary, and the things
/// its buttons do (Pause All, Resume All, Slow Mode).
///
/// Umbra decides what each action does; this only works out which torrents
/// to name and keeps Umbra's refusal, in Umbra's own words, to show as one
/// line in the panel.
@MainActor @Observable
public final class MenuBarModel {
  private let session: AppSession
  private let window: MainWindowModel

  /// The last refusal, as one line for the panel; nil when there is none.
  public private(set) var failureLine: String?
  @ObservationIgnored private var clearTask: Task<Void, Never>?
  /// How long a refusal stays in the panel.
  @ObservationIgnored private let failureLifetime: Duration

  public init(
    session: AppSession, window: MainWindowModel, failureLifetime: Duration = .seconds(10)
  ) {
    self.session = session
    self.window = window
    self.failureLifetime = failureLifetime
  }

  /// What to show now. Reads the live list, so views that call this
  /// redraw when it changes.
  public var summary: MenuBarSummary {
    let store = session.store
    return MenuBarSummary(
      torrents: store.torrents, transfer: store.transfer, phase: session.phase,
      feed: store.state,
      vpn: VpnSummary(
        transfer: store.transfer, status: session.vpnStatus, connection: store.state,
        waking: session.isCheckingVpnAfterWake),
      slowMode: window.slowMode)
  }

  /// Pauses every torrent that can be paused. A refusal is returned, not shown.
  public func pauseAll() async -> ActionFailure? {
    await send(.pause, to: summary.pauseAllHashes)
  }

  /// Resumes every torrent that can be resumed. A refusal is returned, not shown.
  public func resumeAll() async -> ActionFailure? {
    await send(.resume, to: summary.resumeAllHashes)
  }

  /// Turns slow mode on or off. A refusal is returned, not shown.
  public func setSlowMode(_ on: Bool) async -> ActionFailure? {
    guard session.actions != nil, summary.slowModeEnabled else { return nil }
    guard let error = await window.applySlowMode(on, using: session.actions) else { return nil }
    return ActionFailure(
      title: "Couldn't turn slow mode \(on ? "on" : "off")", message: error.message)
  }

  private func send(_ action: TorrentActions.Action, to hashes: [String]) async -> ActionFailure? {
    guard let actions = session.actions, !hashes.isEmpty else { return nil }
    do {
      try await actions.perform(action, on: hashes)
      return nil
    } catch {
      return ActionFailure(action: action, count: hashes.count, message: error.message)
    }
  }

  // MARK: The panel's line

  /// Shows a refusal in the panel for a few seconds ("Couldn't pause 12
  /// torrents: Umbra's reason"). Nil clears the line.
  public func show(_ failure: ActionFailure?) {
    clearTask?.cancel()
    clearTask = nil
    guard let failure else {
      failureLine = nil
      return
    }
    failureLine = "\(failure.title). \(failure.message)"
    clearTask = Task { [weak self, failureLifetime] in
      try? await Task.sleep(for: failureLifetime)
      guard !Task.isCancelled else { return }
      self?.failureLine = nil
    }
  }

  /// A failure from the main menu goes to the window's alert, as every
  /// other menu action does.
  public func alert(_ failure: ActionFailure?) {
    if let failure { window.actionFailure = failure }
  }
}
