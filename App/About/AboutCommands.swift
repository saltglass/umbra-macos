import SwiftUI
import UmbraKit

/// Replaces the standard "About Umbra" menu item with one that opens our
/// own About window (see AboutWindow).
struct AboutCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(replacing: .appInfo) {
      Button("About \(AboutInfo(infoDictionary: Bundle.main.infoDictionary).name)") {
        openWindow(id: "about")
      }
    }
  }
}
