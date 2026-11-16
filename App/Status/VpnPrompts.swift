// The two things every "VPN needs you" button does: open Settings on its
// VPN page, and ask before starting without a VPN.

import AppKit
import SwiftUI
import UmbraKit

@MainActor
enum VpnPrompts {
  /// Asks before starting without a VPN. Always asked, never skipped:
  /// peers would see this Mac's real address. Cancel is the default button
  /// (Return) and Escape cancels too; only a click on "Start Without VPN"
  /// says yes. Returns true only then.
  static func confirmStartWithout(_ question: StartWithoutVpnConfirmation) async -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = question.title
    alert.informativeText = question.message
    // Cancel goes first: that makes it the default button (Return).
    alert.addButton(withTitle: question.cancelButton)
    let start = alert.addButton(withTitle: question.startButton)
    start.hasDestructiveAction = true
    let response: NSApplication.ModalResponse
    if let window = NSApp.keyWindow ?? NSApp.mainWindow {
      response = await alert.beginSheetModal(for: window)
    } else {
      response = alert.runModal()
    }
    return response == .alertSecondButtonReturn
  }
}

extension SettingsPage {
  /// Where the Settings window remembers its page (see `SettingsWindow`).
  static let storageKey = "Settings.page"
}

/// "Open VPN Settings…": the Settings window, on its VPN page.
struct OpenVpnSettingsAction {
  let openSettings: OpenSettingsAction

  @MainActor func callAsFunction() {
    UserDefaults.standard.set(SettingsPage.vpn.rawValue, forKey: SettingsPage.storageKey)
    openSettings()
  }
}
