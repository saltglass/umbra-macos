import SwiftUI
import UmbraKit
import UniformTypeIdentifiers

/// Whatever was dropped on the window, as text: a file's address
/// ("file:///…/a.torrent"), a link's address, or plain text. What it holds
/// is sorted by `IncomingItems` (UmbraKit), the same as files and links
/// that arrive from Finder or a browser.
struct DroppedText: Transferable {
  let text: String

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(importedContentType: .fileURL) { try Self.read($0) }
    DataRepresentation(importedContentType: .url) { try Self.read($0) }
    DataRepresentation(importedContentType: .plainText) { try Self.read($0) }
  }

  private static func read(_ data: Data) throws -> DroppedText {
    guard let text = String(data: data, encoding: .utf8) else {
      throw CocoaError(.fileReadInapplicableStringEncoding)
    }
    return DroppedText(text: text)
  }
}

extension View {
  /// Dropping .torrent files or a magnet link here opens the Add sheet.
  /// Nothing is added until the person presses Add.
  func dropsTorrents(onto presenter: AddTorrentPresenter?) -> some View {
    modifier(DropsTorrents(presenter: presenter))
  }
}

private struct DropsTorrents: ViewModifier {
  let presenter: AddTorrentPresenter?
  @State private var targeted = false

  func body(content: Content) -> some View {
    if let presenter {
      content
        .dropDestination(for: DroppedText.self) { dropped, _ in
          presenter.receive(texts: dropped.map(\.text))
        } isTargeted: {
          targeted = $0
        }
        .overlay {
          if targeted {
            RoundedRectangle(cornerRadius: 8)
              .strokeBorder(Color.accentColor, lineWidth: 3)
              .padding(4)
              .allowsHitTesting(false)
          }
        }
    } else {
      content
    }
  }
}

/// Gives the presenter a way to bring the main window to the front (and
/// open it if it was closed). Put on the main window's content.
struct MainWindowOpener: ViewModifier {
  let presenter: AddTorrentPresenter
  @Environment(\.openWindow) private var openWindow

  func body(content: Content) -> some View {
    content.onAppear {
      presenter.showMainWindow = {
        NSApp.activate()
        // The main window is a single window: this brings it forward, or
        // opens it again if it was closed.
        openWindow(id: "main")
      }
    }
  }
}
