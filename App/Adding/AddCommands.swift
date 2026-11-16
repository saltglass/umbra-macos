import SwiftUI

/// File → Open Torrent… (⌘O: the file panel, then the Add sheet) and
/// File → Add Magnet Link or Web Address… (⌘U: the sheet, ready to paste).
/// Both are dimmed while Umbra isn't connected or the sheet is already open.
/// File → Create Torrent… (⌘N) is here too: it opens the Create Torrent
/// sheet (see App/Creating).
struct AddCommands: Commands {
  let presenter: AddTorrentPresenter

  var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("Create Torrent…") { presenter.creating.showSheet() }
        .keyboardShortcut("n")
        .disabled(!presenter.creating.canOpen || presenter.request != nil)
      Divider()
      Button("Open Torrent…") { presenter.openTorrentFiles() }
        .keyboardShortcut("o")
        .disabled(!presenter.canOpen)
      Button("Add Magnet Link or Web Address…") { presenter.showSheet(focusLink: true) }
        .keyboardShortcut("u")
        .disabled(!presenter.canOpen)
    }
  }
}
