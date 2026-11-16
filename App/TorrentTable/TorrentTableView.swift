import AppKit

/// A key the torrent list hands to its owner instead of handling itself.
enum TorrentListKey: Sendable {
  /// Space (Finder uses it for Quick Look).
  case space
  /// Delete or Forward Delete.
  case delete
}

/// AppKit's table with the few things Finder-style lists do on top:
/// right-clicking a row that isn't selected selects it first, and Space and
/// Delete are offered to the owner before AppKit sees them.
final class TorrentTableView: NSTableView {
  /// The menu for a right-click on the selection; nil shows none.
  var rowMenu: (() -> NSMenu?)?
  /// Space and Delete; returns true if it did something with the key.
  var keyCommand: ((TorrentListKey) -> Bool)?

  override func menu(for event: NSEvent) -> NSMenu? {
    let row = self.row(at: convert(event.locationInWindow, from: nil))
    guard row >= 0 else { return nil }
    // As in Finder: right-click outside the selection selects that one row.
    if !selectedRowIndexes.contains(row) {
      selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }
    return rowMenu?()
  }

  override func keyDown(with event: NSEvent) {
    let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
    if modifiers.isEmpty, let key = Self.listKey(event), keyCommand?(key) == true { return }
    super.keyDown(with: event)
  }

  private static func listKey(_ event: NSEvent) -> TorrentListKey? {
    switch event.charactersIgnoringModifiers {
    case " ": .space
    case String(UnicodeScalar(NSDeleteCharacter)!), String(UnicodeScalar(NSDeleteFunctionKey)!):
      .delete
    default: nil
    }
  }
}

/// The list's scroll view. The first time it has a width, it shrinks the
/// Name column so every column fits, as Finder does; after that AppKit's
/// own resizing (and the person's) takes over.
final class TorrentScrollView: NSScrollView {
  private var fitted = false

  override func tile() {
    super.tile()
    guard !fitted, contentView.bounds.width > 0, let table = documentView as? NSTableView else {
      return
    }
    fitted = true
    table.sizeToFit()
  }
}
