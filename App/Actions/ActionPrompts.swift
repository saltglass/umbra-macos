import AppKit
import UmbraKit
import UniformTypeIdentifiers

/// The windows the torrent actions put up: the Remove alert, the New Tag
/// prompt and the .torrent save panels. Each is a system alert or panel,
/// shown as a sheet on the window when there is one.
@MainActor
enum ActionPrompts {
  /// Where sheets hang from.
  private static var window: NSWindow? { NSApp.keyWindow ?? NSApp.mainWindow }

  // MARK: Remove

  /// Asks whether to remove. Returns nil if the person cancelled, otherwise
  /// whether to delete the downloaded files too (the tick box, off each time).
  static func confirmRemoval(_ confirmation: RemoveConfirmation) async -> Bool? {
    let prompt = RemovalAlert(confirmation)
    let response = await run(prompt.alert)
    withExtendedLifetime(prompt) {}
    return response == .alertSecondButtonReturn ? prompt.box.state == .on : nil
  }

  /// The Remove alert, built but not shown: its tick box and its Remove
  /// button change their words as the box is ticked. The pictures in
  /// `just snapshot` draw this same alert.
  @MainActor
  final class RemovalAlert: NSObject {
    let alert = NSAlert()
    let box: NSButton
    let remove: NSButton
    let confirmation: RemoveConfirmation

    init(_ confirmation: RemoveConfirmation) {
      self.confirmation = confirmation
      alert.alertStyle = .warning
      alert.messageText = confirmation.title
      alert.informativeText = confirmation.message(deletingFiles: false)

      // Cancel goes first: that makes it the default button (Return), the
      // safe choice for something that can't be undone. Escape cancels too.
      alert.addButton(withTitle: confirmation.cancelButton)
      remove = alert.addButton(withTitle: confirmation.removeButton(deletingFiles: false))
      remove.hasDestructiveAction = true

      // The tick box is off every time the alert opens.
      box = NSButton(checkboxWithTitle: confirmation.deleteFilesLabel, target: nil, action: nil)
      box.state = .off
      super.init()
      box.target = self
      box.action = #selector(changed(_:))
      fitBox()
      alert.accessoryView = box
    }

    /// Changes the alert's words as the box is ticked: deleting the files
    /// is said outright, since there is no Trash to get them back from. For
    /// the person's own files the Remove button says so too.
    @objc func changed(_ box: NSButton) {
      let deleting = box.state == .on
      alert.informativeText = confirmation.message(deletingFiles: deleting)
      remove.title = confirmation.removeButton(deletingFiles: deleting)
      alert.layout()
    }

    /// A long label (the person's own files) wraps instead of widening the
    /// alert past its usual size.
    private func fitBox() {
      box.sizeToFit()
      let widest: CGFloat = 300
      guard box.frame.width > widest else { return }
      box.cell?.wraps = true
      box.cell?.lineBreakMode = .byWordWrapping
      let size = box.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: widest, height: 1000))
      box.frame.size = NSSize(width: widest, height: size?.height ?? box.frame.height)
    }
  }

  // MARK: New tag

  /// Asks for a tag's name. Nil if cancelled; never empty.
  static func askForTag(count: Int) async -> String? {
    let alert = NSAlert()
    alert.messageText = "New Tag"
    alert.informativeText =
      count == 1
      ? "Give the selected torrent a new tag."
      : "Give the \(Format.count(count)) selected torrents a new tag."
    let add = alert.addButton(withTitle: "Add")
    alert.addButton(withTitle: "Cancel")
    add.isEnabled = false

    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
    field.placeholderString = "Tag name"
    let watcher = TextWatcher(button: add)
    field.delegate = watcher
    alert.accessoryView = field
    alert.window.initialFirstResponder = field

    let response = await run(alert)
    withExtendedLifetime(watcher) {}
    guard response == .alertFirstButtonReturn else { return nil }
    let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? nil : name
  }

  /// Keeps the Add button dimmed while the field is empty.
  @MainActor
  private final class TextWatcher: NSObject, NSTextFieldDelegate {
    let button: NSButton
    init(button: NSButton) { self.button = button }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      button.isEnabled = !field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
    }
  }

  // MARK: Export

  /// Asks where to save one .torrent file; nil if cancelled.
  static func chooseTorrentFile(named name: String) async -> URL? {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = name
    panel.canCreateDirectories = true
    panel.message = "Save the .torrent file"
    if let type = UTType(filenameExtension: "torrent") { panel.allowedContentTypes = [type] }
    return await run(panel) ? panel.url : nil
  }

  /// Asks for a folder to save several .torrent files in; nil if cancelled.
  static func chooseTorrentFolder(count: Int) async -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Export"
    panel.message = "Choose a folder for the \(Format.count(count)) .torrent files"
    return await run(panel) ? panel.url : nil
  }

  // MARK: Showing them

  private static func run(_ alert: NSAlert) async -> NSApplication.ModalResponse {
    guard let window else { return alert.runModal() }
    return await alert.beginSheetModal(for: window)
  }

  private static func run(_ panel: NSSavePanel) async -> Bool {
    let response: NSApplication.ModalResponse
    if let window {
      response = await panel.beginSheetModal(for: window)
    } else {
      response = panel.runModal()
    }
    return response == .OK
  }
}
