import AppKit
import SwiftUI
import UmbraKit

/// Opens the Create Torrent sheet (File → Create Torrent…).
/// The sheet's logic is `CreateTorrentModel` (UmbraKit); this adds only the
/// Mac's parts: the open panel and the save panel.
///
/// The Mac app never reads the files or builds the .torrent itself. It
/// hands Umbra the path chosen in the open panel, and Umbra does the rest.
@MainActor @Observable
final class CreateTorrentPresenter {
  /// One showing of the sheet, with its own model.
  struct Request: Identifiable {
    let id = UUID()
    let model: CreateTorrentModel
  }

  /// The sheet being shown; nil when it's closed.
  var request: Request?

  @ObservationIgnored let session: AppSession
  @ObservationIgnored let window: MainWindowModel

  init(session: AppSession, window: MainWindowModel) {
    self.session = session
    self.window = window
  }

  /// Whether a sheet can open: Umbra is connected and none is open.
  var canOpen: Bool { session.creationActions != nil && request == nil }

  /// File → Create Torrent…: the sheet, empty.
  func showSheet() {
    guard canOpen, let actions = session.creationActions else { return }
    let window = self.window
    request = Request(
      model: CreateTorrentModel(actions: actions, select: { window.selectWhenListed($0) }))
  }

  /// The sheet has gone: lets go of everything it asked Umbra for
  /// (this also cancels a torrent still being made).
  func sheetClosed(_ closed: Request) {
    if request?.id == closed.id { request = nil }
    let model = closed.model
    Task { await model.close() }
  }

  // MARK: The open and save panels

  /// "Choose File or Folder…": one file or folder on this Mac.
  func chooseItem(for model: CreateTorrentModel) {
    Task {
      let panel = NSOpenPanel()
      panel.title = "Create Torrent"
      panel.message = "Choose the file or folder to make a torrent of."
      panel.prompt = "Choose"
      panel.canChooseFiles = true
      panel.canChooseDirectories = true
      panel.allowsMultipleSelection = false
      panel.canCreateDirectories = false
      guard await Self.run(panel) == .OK, let url = panel.url else { return }
      model.choose(url: url)
    }
  }

  /// "Save .torrent File…": asks where, then has Umbra's file written there.
  func saveTorrentFile(of model: CreateTorrentModel) {
    Task {
      let panel = NSSavePanel()
      panel.title = "Save Torrent File"
      panel.nameFieldStringValue = model.suggestedFileName
      panel.allowedContentTypes = [AddTorrentPresenter.torrentType]
      panel.canCreateDirectories = true
      guard await Self.run(panel) == .OK, let url = panel.url else { return }
      await model.saveTorrentFile(to: url)
    }
  }

  /// Shows a panel as a sheet on the frontmost window (the Create sheet).
  private static func run(_ panel: NSSavePanel) async -> NSApplication.ModalResponse {
    if let window = NSApp.keyWindow ?? NSApp.mainWindow {
      return await panel.beginSheetModal(for: window)
    }
    return await withCheckedContinuation { done in panel.begin { done.resume(returning: $0) } }
  }
}

extension View {
  /// The Create Torrent sheet, shown while the presenter has a request.
  func createTorrentSheet(_ presenter: CreateTorrentPresenter?) -> some View {
    modifier(CreateTorrentSheetModifier(presenter: presenter))
  }
}

private struct CreateTorrentSheetModifier: ViewModifier {
  let presenter: CreateTorrentPresenter?

  func body(content: Content) -> some View {
    if let presenter {
      @Bindable var presenter = presenter
      content
        .sheet(item: $presenter.request) { request in
          CreateSheet(
            model: request.model, creations: presenter.session.store.creations,
            chooseItem: { presenter.chooseItem(for: request.model) },
            saveFile: { presenter.saveTorrentFile(of: request.model) }
          )
          .onDisappear { presenter.sheetClosed(request) }
        }
    } else {
      content
    }
  }
}
