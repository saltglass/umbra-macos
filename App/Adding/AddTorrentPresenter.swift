import AppKit
import SwiftUI
import UmbraKit
import UniformTypeIdentifiers

/// Opens the Add sheet, from the toolbar's Add button and the File menu.
/// The sheet's logic is `AddTorrentModel` (UmbraKit); this adds only the
/// Mac's parts: the open panel.
///
/// Opening the sheet never reads the pasteboard: that would start Umbra
/// fetching something the person didn't choose, and macOS 26 asks for
/// permission each time an app reads it on its own. The person pastes
/// into the link field with ⌘V like any text field.
///
/// One of these is made at launch and shared by the toolbar, the menu and
/// the window (which shows the sheet while `request` is set).
@MainActor @Observable
final class AddTorrentPresenter {
  /// One showing of the sheet, with its own model.
  struct Request: Identifiable {
    let id = UUID()
    let model: AddTorrentModel
    /// Put the cursor in the link field (File → Add Magnet Link…).
    let focusLink: Bool
  }

  /// The sheet being shown; nil when it's closed.
  var request: Request?

  @ObservationIgnored let session: AppSession
  @ObservationIgnored let window: MainWindowModel
  /// File → Create Torrent…, which lives beside the Add sheet.
  @ObservationIgnored let creating: CreateTorrentPresenter

  init(session: AppSession, window: MainWindowModel) {
    self.session = session
    self.window = window
    self.creating = CreateTorrentPresenter(session: session, window: window)
  }

  /// Whether a new sheet can open: Umbra is connected and none is open
  /// (neither this one nor the Create Torrent sheet).
  var canOpen: Bool { session.actions != nil && request == nil && creating.request == nil }

  // MARK: Ways in

  /// The toolbar's Add button, and File → Add Magnet Link or Web Address…
  /// (which puts the cursor in the link field): the sheet, empty.
  func showSheet(focusLink: Bool = false) {
    guard canOpen, let model = makeModel() else { return }
    request = Request(model: model, focusLink: focusLink)
  }

  /// File → Open Torrent…: the open panel first, then the sheet with the
  /// files chosen. Cancelling the panel opens nothing.
  func openTorrentFiles() {
    guard canOpen else { return }
    Task {
      guard let urls = await Self.chooseTorrentFiles(), !urls.isEmpty, canOpen,
        let model = makeModel()
      else { return }
      model.choose(fileURLs: urls)
      request = Request(model: model, focusLink: false)
    }
  }

  /// The sheet's Choose File… button: the open panel over the sheet.
  func chooseFiles(for model: AddTorrentModel) {
    Task {
      guard let urls = await Self.chooseTorrentFiles(), !urls.isEmpty else { return }
      model.choose(fileURLs: urls)
    }
  }

  // MARK: Things arriving from outside

  /// Brings the main window to the front, opening it if it was closed.
  /// Set by the window itself (see `MainWindowOpener`).
  @ObservationIgnored var showMainWindow: @MainActor () -> Void = {}

  /// What has arrived and is waiting for a sheet.
  @ObservationIgnored private var incoming = IncomingItems()

  /// .torrent files or magnet links opened in Umbra (double-click, Dock
  /// icon, a link in a browser). Anything else is ignored.
  func receive(urls: [URL]) {
    guard incoming.add(urls: urls) else { return }
    arrived()
  }

  /// Things dropped on the window, as text (see `DroppedText`): magnet
  /// links and addresses of .torrent files. All are taken before the sheet
  /// opens, so several files dropped together share one sheet. True if
  /// anything in them was wanted.
  @discardableResult
  func receive(texts: [String]) -> Bool {
    var wanted = false
    for text in texts where incoming.add(text: text) { wanted = true }
    if wanted { arrived() }
    return wanted
  }

  private func arrived() {
    showMainWindow()
    deliverIncoming()
  }

  /// Opens the sheet for what is waiting, if one can open now. Called when
  /// something arrives and whenever `canOpen` turns true again (Umbra
  /// connected, or the open sheet closed), so the rest follows in turn.
  /// Never adds anything: the person presses Add.
  func deliverIncoming() {
    guard !incoming.isEmpty, canOpen, let model = makeModel(),
      let batch = incoming.nextBatch(ready: true)
    else { return }
    switch batch {
    case .files(let urls): model.choose(fileURLs: urls)
    case .magnet(let link): model.choose(link: link)
    }
    request = Request(model: model, focusLink: false)
  }

  /// The sheet has gone (Add, Cancel or Escape): lets go of everything.
  func sheetClosed(_ closed: Request) {
    closed.model.close()
    if request?.id == closed.id { request = nil }
  }

  private func makeModel() -> AddTorrentModel? {
    guard let actions = session.actions else { return nil }
    let window = self.window
    return AddTorrentModel(
      actions: actions,
      categories: window.definedCategories + window.counts.categories.keys.sorted(),
      tags: Array(window.counts.tags.keys),
      select: { window.selectWhenListed($0) })
  }

  // MARK: The open panel

  /// .torrent files. macOS has no type of its own for them; the app declares
  /// one in its Info.plist (see project.yml). The file name ending is the
  /// fallback if macOS hasn't read that yet.
  static var torrentType: UTType {
    UTType("org.bittorrent.torrent") ?? UTType(filenameExtension: "torrent", conformingTo: .data)
      ?? .data
  }

  /// Asks for .torrent files (several may be chosen); nil if cancelled.
  /// Shown as a sheet on the frontmost window (the Add sheet, when open).
  static func chooseTorrentFiles() async -> [URL]? {
    let panel = NSOpenPanel()
    panel.title = "Open Torrent"
    panel.message = "Choose one or more .torrent files to add."
    panel.prompt = "Open"
    panel.allowedContentTypes = [torrentType]
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    let response: NSApplication.ModalResponse
    if let window = NSApp.keyWindow ?? NSApp.mainWindow {
      response = await panel.beginSheetModal(for: window)
    } else {
      response = await withCheckedContinuation { done in panel.begin { done.resume(returning: $0) }
      }
    }
    return response == .OK ? panel.urls : nil
  }
}

extension EnvironmentValues {
  /// The shared presenter; nil in pictures of the views (Add is then dimmed).
  @Entry var addTorrents: AddTorrentPresenter?
}

extension View {
  /// The Add sheet, shown while the presenter has a request.
  func addTorrentSheet(_ presenter: AddTorrentPresenter?, freeSpace: String?) -> some View {
    modifier(AddTorrentSheetModifier(presenter: presenter, freeSpace: freeSpace))
  }
}

private struct AddTorrentSheetModifier: ViewModifier {
  let presenter: AddTorrentPresenter?
  let freeSpace: String?

  func body(content: Content) -> some View {
    if let presenter {
      @Bindable var presenter = presenter
      content
        // Files and links that arrived early or while a sheet was open.
        .task(id: presenter.canOpen) { presenter.deliverIncoming() }
        .sheet(item: $presenter.request) { request in
          AddSheet(
            model: request.model, freeSpace: freeSpace, focusLink: request.focusLink,
            chooseFiles: { presenter.chooseFiles(for: request.model) }
          )
          .onDisappear { presenter.sheetClosed(request) }
        }
    } else {
      content
    }
  }
}
