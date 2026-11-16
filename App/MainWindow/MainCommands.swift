import SwiftUI
import UmbraKit

/// The main window's menu items: View → Show/Hide Inspector (⌥⌘I) and
/// Edit → Find… (⌘F, which puts the cursor in the search field).
struct MainCommands: Commands {
  let model: MainWindowModel

  var body: some Commands {
    CommandGroup(after: .sidebar) {
      Button(model.inspectorShown ? "Hide Inspector" : "Show Inspector") {
        model.inspectorShown.toggle()
      }
      .keyboardShortcut("i", modifiers: [.command, .option])
    }
    // Replaces the text-editing Find submenu, whose ⌘F would look for a
    // text view instead of going to the toolbar's search field.
    CommandGroup(replacing: .textEditing) {
      Button("Find…") { model.requestSearchFocus() }
        .keyboardShortcut("f")
    }
  }
}
