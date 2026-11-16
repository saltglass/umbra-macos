// Extra building blocks for settings pages that pick folders: the Mac's
// own folder panel, and a row showing a folder with Choose… and a way to
// go back. See SettingsParts.swift for the common ones.

import AppKit
import SwiftUI
import UmbraKit

/// The Mac's folder panel.
enum FolderPanel {
  /// Asks for a folder, starting at `startingAt` when that is one that
  /// exists. Returns its full path, or nil if cancelled. It slides out of
  /// the window that is in front, as the system's panels do.
  @MainActor
  static func choose(
    startingAt: String, message: String, prompt: String = "Choose"
  ) async -> String? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = prompt
    panel.message = message
    var isFolder: ObjCBool = false
    if !startingAt.isEmpty,
      FileManager.default.fileExists(atPath: startingAt, isDirectory: &isFolder), isFolder.boolValue
    {
      panel.directoryURL = URL(fileURLWithPath: startingAt, isDirectory: true)
    }
    let response: NSApplication.ModalResponse
    if let window = NSApp.keyWindow {
      response = await panel.beginSheetModal(for: window)
    } else {
      response = panel.runModal()
    }
    return response == .OK ? panel.url?.path : nil
  }
}

/// A folder setting in a form: the label and its explanation on the left;
/// on the right the folder (the home folder as `~`, the full path in a
/// tooltip) with Choose… and a button to go back to none or the default.
struct SettingsFolderRow: View {
  let title: String
  /// One line saying what the setting does (the web page's wording).
  var help: String?
  /// The folder, or "" for none.
  let path: String
  /// Shown, dimmed, when there is no folder: "Off", or the default folder.
  let whenEmpty: String
  /// The button that clears the folder ("Turn Off", "Use Default").
  let clearTitle: String
  /// The panel's one-line prompt.
  let panelMessage: String
  /// Dim the "whenEmpty" text (for "Off"). Off for a default folder, which
  /// is the folder in use and reads as any other.
  var dimWhenEmpty = true
  /// The tooltip when there is no folder chosen (what the empty state means).
  var emptyTooltip: String?
  /// Umbra's message when it refused this folder.
  var problem: String?
  /// A folder was chosen: its full path.
  let onChoose: (String) -> Void
  let onClear: () -> Void

  var body: some View {
    LabeledContent {
      VStack(alignment: .trailing, spacing: 6) {
        Text(FolderPath.abbreviated(path.isEmpty ? whenEmpty : path))
          .foregroundStyle(path.isEmpty && dimWhenEmpty ? .tertiary : .secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(path.isEmpty ? (emptyTooltip ?? whenEmpty) : path)
        HStack(spacing: 8) {
          Button("Choose…") {
            Task {
              if let chosen = await FolderPanel.choose(startingAt: path, message: panelMessage) {
                onChoose(chosen)
              }
            }
          }
          Button(clearTitle, action: onClear)
            .disabled(path.isEmpty)
        }
      }
    } label: {
      Text(title)
      if let help { Text(help) }
      SettingsProblem(message: problem)
    }
  }
}
