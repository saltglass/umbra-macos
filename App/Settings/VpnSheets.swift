// The VPN page's sheets: pasting a configuration, and renaming or editing
// a saved VPN. Each stays open when Umbra refuses and shows Umbra's own
// words; it closes only once Umbra has saved the change.
//
// A configuration holds a private key. While a sheet is open it lives only
// in the sheet (never in a file, the defaults or the pasteboard, and never
// printed); once Umbra has it, or the sheet closes, it is emptied.

import AppKit
import SwiftUI
import UmbraAPI
import UmbraKit
import UniformTypeIdentifiers

/// Which sheet the VPN page shows.
enum VpnSheet: Identifiable {
  /// Paste a configuration. A refusal is given only for pictures.
  case paste(UmbraError?)
  /// Rename or edit the saved VPN with this id.
  case edit(String)

  var id: String {
    switch self {
    case .paste: "paste"
    case .edit(let id): "edit-\(id)"
    }
  }
}

/// The system's open panel for a WireGuard .conf file.
@MainActor
enum ConfigFilePanel {
  /// Asks for one .conf (or plain text) file; nil if cancelled. Nothing is
  /// read here: the caller reads it once, sends it, and drops it.
  static func choose() async -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Add"
    panel.message = "Choose the WireGuard .conf file from your VPN provider."
    panel.allowedContentTypes = [UTType(filenameExtension: "conf"), .plainText].compactMap { $0 }
    let response: NSApplication.ModalResponse
    if let window = NSApp.keyWindow {
      response = await panel.beginSheetModal(for: window)
    } else {
      response = panel.runModal()
    }
    return response == .OK ? panel.url : nil
  }
}

// MARK: Paste

struct VpnPasteSheet: View {
  let model: VpnSettingsModel

  @Environment(\.dismiss) private var dismiss
  /// The name and the pasted text (a secret: see `VpnPasteDraft`).
  @State private var draft = VpnPasteDraft()
  @State private var saving = false
  /// Umbra's words when it refused the configuration.
  @State private var problem: String?

  init(model: VpnSettingsModel, refusal: UmbraError? = nil) {
    self.model = model
    _problem = State(initialValue: refusal.map(VpnSettingsModel.explanation))
  }

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          TextField("Name", text: $draft.name, prompt: Text("Optional: the server's name"))
          VStack(alignment: .leading, spacing: 6) {
            Text("WireGuard configuration")
            TextEditor(text: $draft.text)
              .font(.system(.body, design: .monospaced))
              .autocorrectionDisabled()
              .writingToolsBehavior(.disabled)
              .frame(height: 170)
              .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator))
              .accessibilityLabel("WireGuard configuration")
          }
        } footer: {
          VStack(alignment: .leading, spacing: 6) {
            Text(
              "Paste the whole .conf file from your VPN provider, from [Interface] to the end. "
                + "It goes straight to Umbra, which stores its private key encrypted; this Mac "
                + "keeps no copy."
            )
            .foregroundStyle(.secondary)
            SettingsProblem(message: problem)
          }
          .font(.callout)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .formStyle(.grouped)

      HStack {
        if saving { ProgressView().controlSize(.small) }
        Spacer()
        Button("Cancel", role: .cancel) { close() }
          .keyboardShortcut(.cancelAction)
        Button("Add", action: save)
          .keyboardShortcut(.defaultAction)
          .disabled(draft.isBlank || saving)
      }
      .padding([.horizontal, .bottom], 20)
      .padding(.top, 4)
    }
    .frame(width: 500, height: 420)
    // However the sheet goes, the text goes with it.
    .onDisappear { draft.clear() }
  }

  private func save() {
    guard !draft.isBlank, !saving else { return }
    saving = true
    problem = nil
    Task {
      let refusal = await model.add(draft)
      saving = false
      if let refusal {
        // Kept only while the sheet stays open, so it can be corrected.
        problem = VpnSettingsModel.explanation(for: refusal)
      } else {
        close()
      }
    }
  }

  private func close() {
    draft.clear()
    dismiss()
  }
}

// MARK: Edit

/// A saved VPN's name, forwarded port and file.
struct VpnEditSheet: View {
  let model: VpnSettingsModel
  let vpn: Components.Schemas.VpnProfile

  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var port: String
  /// A replacement file, read once it was chosen; sent with Save.
  @State private var replacement: (file: String, configuration: VpnConfiguration)?
  @State private var saving = false
  @State private var refusal: UmbraError?

  init(model: VpnSettingsModel, vpn: Components.Schemas.VpnProfile) {
    self.model = model
    self.vpn = vpn
    _name = State(initialValue: vpn.name)
    _port = State(initialValue: vpn.forwardedPort.map { $0 > 0 ? String($0) : "" } ?? "")
  }

  /// The typed port: blank is none (0); nil when it isn't a whole number.
  private var portNumber: Int? {
    let trimmed = port.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? 0 : Int(trimmed)
  }

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          TextField("Name", text: $name)
            .onSubmit(save)
          SettingsProblem(message: refusal?.fields["name"])
          LabeledContent {
            TextField("Forwarded port", text: $port, prompt: Text("None"))
              .labelsHidden()
              .textFieldStyle(.roundedBorder)
              .multilineTextAlignment(.trailing)
              .monospacedDigit()
              .frame(width: 80)
          } label: {
            Text("Forwarded port")
            Text(
              "The port your VPN provider forwards to this VPN, set up on its website, so peers "
                + "can connect in. Empty: none.")
            SettingsProblem(
              message: portNumber == nil
                ? "A port is a whole number." : refusal?.fields["forwardedPort"])
          }
          LabeledContent {
            Button("Choose New File…") { chooseFile() }
          } label: {
            Text("WireGuard file")
            Text(
              replacement.map { "“\($0.file)” replaces the saved file." }
                ?? "Keep the saved file, or choose a new one.")
            SettingsProblem(message: refusal?.fields["config"])
          }
        } footer: {
          VStack(alignment: .leading, spacing: 6) {
            if vpn.inUse {
              Text("It's in use: a new file or port restarts every torrent for a few seconds.")
                .foregroundStyle(.secondary)
            }
            SettingsProblem(message: refusal.flatMap { $0.fields.isEmpty ? $0.message : nil })
          }
          .font(.callout)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .formStyle(.grouped)

      HStack {
        if saving { ProgressView().controlSize(.small) }
        Spacer()
        Button("Cancel", role: .cancel) { close() }
          .keyboardShortcut(.cancelAction)
        Button("Save", action: save)
          .keyboardShortcut(.defaultAction)
          .disabled(saving || portNumber == nil)
      }
      .padding([.horizontal, .bottom], 20)
      .padding(.top, 4)
    }
    .frame(width: 500, height: 360)
    .onDisappear { replacement = nil }
  }

  private func chooseFile() {
    Task {
      guard let url = await ConfigFilePanel.choose() else { return }
      do {
        replacement = (url.lastPathComponent, try VpnSettingsModel.readConfiguration(at: url))
      } catch {
        refusal = UmbraError(
          code: "unreadable", message: "Couldn't read “\(url.lastPathComponent)”.")
      }
    }
  }

  private func save() {
    guard let port = portNumber, !saving else { return }
    saving = true
    Task {
      let answer = await model.edit(
        vpn.id, name: name, forwardedPort: port, configuration: replacement?.configuration)
      saving = false
      if let answer {
        refusal = answer
      } else {
        close()
      }
    }
  }

  private func close() {
    replacement = nil
    dismiss()
  }
}
