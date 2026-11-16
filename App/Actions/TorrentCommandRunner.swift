import AppKit
import SwiftUI
import UmbraKit

/// Carries out what the torrent menu, the toolbar and the keyboard ask for.
/// The logic is in UmbraKit (`MainWindowModel`); this adds only what needs
/// the Mac: alerts and panels, the pasteboard and Finder.
///
/// One of these is made at launch and shared by the right-click menu, the
/// menu bar's Torrent menu and the list's keys.
@MainActor
final class TorrentCommandRunner: NSObject {
  let session: AppSession
  let model: MainWindowModel
  /// True while an alert or panel is open, so a second Remove (a key held
  /// down, say) can't stack another.
  private var promptOpen = false

  init(session: AppSession, model: MainWindowModel) {
    self.session = session
    self.model = model
  }

  /// The menu bar item's actions (Pause All, Resume All, Slow Mode); the
  /// menu bar's Torrent menu uses the same ones.
  lazy var menuBar = MenuBarModel(session: session, window: model)

  /// Whether Umbra is connected (nothing can be done without it).
  var connected: Bool { session.actions != nil }
  var actions: TorrentActions? { session.actions }

  // MARK: Doing things

  func run(_ command: TorrentMenuCommand) {
    let actions = self.actions
    switch command {
    case .run(let action):
      Task { await model.perform(action, using: actions) }
    case .setCategory(let category):
      Task { await model.setCategory(category, using: actions) }
    case .changeTag(let tag, let add):
      Task { await model.changeTag(tag, add: add, using: actions) }
    case .newTag:
      prompt { await self.askForNewTag() }
    case .copyMagnetLinks:
      Task { await self.copy(.magnetLinks) }
    case .copyInfoHashes:
      Task { await self.copy(.infoHashes) }
    case .exportTorrents:
      prompt { await self.exportTorrents() }
    case .showInFinder:
      showInFinder()
    case .moveData:
      prompt { await self.askToMove() }
    case .editLimits:
      model.showLimits()
    case .remove:
      if typingInAField { return }
      prompt { await self.askToRemove() }
    case .setSlowMode(let on):
      Task { await model.setSlowMode(on, using: actions) }
    }
  }

  /// Runs something that puts up a prompt, one at a time.
  private func prompt(_ work: @escaping () async -> Void) {
    guard !promptOpen else { return }
    promptOpen = true
    Task {
      await work()
      promptOpen = false
    }
  }

  /// ⌘⌫ in the search field means "delete to the start of the line", not
  /// Remove: the menu's shortcut would otherwise take it. Do what the field
  /// would have done and say it was handled.
  private var typingInAField: Bool {
    guard NSApp.currentEvent?.type == .keyDown, NSApp.keyWindow?.firstResponder is NSText else {
      return false
    }
    NSApp.sendAction(#selector(NSResponder.deleteToBeginningOfLine(_:)), to: nil, from: nil)
    return true
  }

  // MARK: Remove

  private func askToRemove() async {
    guard connected, let confirmation = model.removeConfirmation() else { return }
    guard let deleteFiles = await ActionPrompts.confirmRemoval(confirmation) else { return }
    await model.remove(confirmation, deleteFiles: deleteFiles, using: actions)
  }

  // MARK: Move Data To…

  /// Asks for a folder (starting at the first torrent's own), then asks
  /// Umbra to move the selected torrents' files there. Umbra says if it
  /// can't, and the alert shows its words.
  private func askToMove() async {
    let hashes = model.selectedHashes
    let count = hashes.count
    guard connected, count > 0 else { return }
    let message =
      count == 1
      ? "Choose the folder to move the torrent's files to."
      : "Choose the folder to move the files of the \(Format.count(count)) torrents to."
    guard
      let folder = await FolderPanel.choose(
        startingAt: model.firstSaveFolder, message: message, prompt: "Move")
    else { return }
    await model.move(hashes, to: folder, using: actions)
  }

  // MARK: Tags

  private func askForNewTag() async {
    let count = model.selection.count
    guard connected, count > 0, let tag = await ActionPrompts.askForTag(count: count) else {
      return
    }
    await model.changeTag(tag, add: true, using: actions)
  }

  // MARK: Copying, exporting, Finder

  private func copy(_ kind: MainWindowModel.CopyKind) async {
    guard let text = await model.copyText(kind, using: actions) else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  private func exportTorrents() async {
    let rows = model.selectedRows
    guard connected, let first = rows.first else { return }
    let destination =
      rows.count == 1
      ? await ActionPrompts.chooseTorrentFile(named: TorrentFiles.exportName(for: first))
      : await ActionPrompts.chooseTorrentFolder(count: rows.count)
    guard let destination else { return }
    await model.exportTorrents(to: destination, using: actions)
  }

  /// Shows each torrent's files in Finder; for one whose files aren't
  /// there (yet), its save folder.
  private func showInFinder() {
    let manager = FileManager.default
    var urls: [URL] = []
    for row in model.selectedRows {
      for url in [TorrentFiles.location(of: row), TorrentFiles.folder(of: row)]
      where manager.fileExists(atPath: url.path) {
        if !urls.contains(url) { urls.append(url) }
        break
      }
    }
    guard !urls.isEmpty else {
      model.actionFailure = ActionFailure(
        title: "Couldn't show the files in Finder",
        message:
          "Umbra hasn't saved any files for the selection yet, or they were moved or deleted outside Umbra."
      )
      return
    }
    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }

  // MARK: The list

  /// The right-click menu for the torrents selected in the list.
  func contextMenu(for hashes: Set<String>) -> NSMenu? {
    guard !hashes.isEmpty else { return nil }
    let menu = model.torrentMenu(for: hashes, connected: connected)
    return TorrentNSMenu.make(
      menu.entries, target: self, action: #selector(menuItemChosen(_:)))
  }

  @objc private func menuItemChosen(_ item: NSMenuItem) {
    guard let command = (item as? TorrentMenuNSItem)?.command else { return }
    run(command)
  }

  /// Space and Delete in the list; true if used.
  func handle(_ key: TorrentListKey) -> Bool {
    guard connected, !model.selection.isEmpty else { return false }
    switch key {
    case .space: return model.spaceBar(using: actions)
    case .delete:
      run(.remove)
      return true
    }
  }

  /// A double-click on a row opens the inspector (the row is selected by then).
  func openInspector() { model.inspectorShown = true }
}

extension EnvironmentValues {
  /// The shared runner; nil in pictures of the views, which then have no menus.
  @Entry var torrentCommands: TorrentCommandRunner?
}
