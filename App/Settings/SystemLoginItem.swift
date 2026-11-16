import AppKit
import ServiceManagement
import UmbraKit

/// The real `LoginItemService`: macOS's login items, through
/// `SMAppService.mainApp`. Pictures of the views never use this one.
@MainActor
struct SystemLoginItem: LoginItemService {
  func status() -> LoginItemStatus {
    switch SMAppService.mainApp.status {
    case .enabled: .on
    case .requiresApproval: .needsApproval
    case .notFound: .unavailable
    case .notRegistered: .off
    @unknown default: .off
    }
  }

  func register() throws { try SMAppService.mainApp.register() }
  func unregister() throws { try SMAppService.mainApp.unregister() }
  func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
