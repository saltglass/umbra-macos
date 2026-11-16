// Settings → General → "Backup": save a backup to a file, or restore from
// one. The logic and every word are in UmbraKit's `BackupModel`; this view
// only shows the system's save and open panels and the warning before a
// restore.

import AppKit
import SwiftUI
import UmbraKit
import UniformTypeIdentifiers

struct BackupSection: View {
  let model: BackupModel

  var body: some View {
    Section {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Button(BackupModel.saveButton) { chooseWhereToSave() }
          Button(BackupModel.restoreButton) { chooseWhatToRestore() }
          if let working = model.activityText {
            ProgressView().controlSize(.small)
            Text(working)
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
        .disabled(!model.isEnabled)
        if let status = model.status {
          Text(status)
            .font(.callout)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        }
        SettingsProblem(message: model.problem)
          .font(.callout)
      }
    } header: {
      Text("Backup")
    } footer: {
      Text("\(BackupModel.contents) \(BackupModel.keepPrivate)")
        .font(.callout)
    }
  }

  /// Umbra's backups are .tar.gz files.
  private static let fileTypes: [UTType] = [.gzip]

  private func chooseWhereToSave() {
    let panel = NSSavePanel()
    panel.title = "Save a Backup"
    panel.nameFieldStringValue = BackupModel.suggestedFileName(at: .now)
    panel.allowedContentTypes = Self.fileTypes
    panel.canCreateDirectories = true
    present(panel) { url in Task { await model.save(to: url) } }
  }

  private func chooseWhatToRestore() {
    let panel = NSOpenPanel()
    panel.title = "Restore from Backup"
    panel.prompt = "Choose"
    panel.allowedContentTypes = Self.fileTypes
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    present(panel) { url in
      model.askToRestore(url)
      // Once the open panel has gone from the window.
      Task { @MainActor in confirmRestore() }
    }
  }

  /// The warning before a restore. Cancel is the default button (Return),
  /// so only a click on Replace goes ahead.
  private func confirmRestore() {
    guard model.pendingRestore != nil else { return }
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = BackupModel.alertTitle
    alert.informativeText = model.alertMessage
    alert.addButton(withTitle: BackupModel.alertCancel)  // first: the default
    let replace = alert.addButton(withTitle: BackupModel.alertConfirm)
    replace.hasDestructiveAction = true
    let decide: (NSApplication.ModalResponse) -> Void = { response in
      if response == .alertSecondButtonReturn {
        Task { await model.confirmRestore() }
      } else {
        model.cancelRestore()
      }
    }
    if let window = NSApp.keyWindow {
      alert.beginSheetModal(for: window, completionHandler: decide)
    } else {
      decide(alert.runModal())
    }
  }

  /// Shows a panel over the Settings window (or on its own), and hands
  /// over the file chosen, if any.
  private func present(_ panel: NSSavePanel, then use: @escaping (URL) -> Void) {
    let done: (NSApplication.ModalResponse) -> Void = { response in
      guard response == .OK, let url = panel.url else { return }
      use(url)
    }
    if let window = NSApp.keyWindow {
      panel.beginSheetModal(for: window, completionHandler: done)
    } else {
      done(panel.runModal())
    }
  }
}
