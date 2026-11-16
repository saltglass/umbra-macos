import AppKit
import SwiftUI
import UmbraKit
import UniformTypeIdentifiers

/// Window → Logs: Umbra's log, live. The window opens the log when it
/// appears and closes the stream when it goes away; everything it decides
/// is in `LogsModel`.
struct LogsWindow: View {
  let session: AppSession
  @State private var model = LogsModel()

  var body: some View {
    LogsView(model: model)
      .frame(minWidth: 520, minHeight: 260)
      .task(id: session.connection) { model.open(connection: session.connection) }
      .onDisappear { model.close() }
  }
}

/// The window's contents. Only draws what the model says.
struct LogsView: View {
  @Bindable var model: LogsModel
  /// Where AppKit remembers the table's columns; nil for pictures.
  var tableAutosaveName: String? = "LogsTable"
  @State private var saveFailure: String?

  var body: some View {
    VStack(spacing: 0) {
      if model.phase == .notConnected {
        ContentUnavailableView(
          "Not Connected", systemImage: "powerplug",
          description: Text("Umbra isn't running, so there is no log to show."))
      } else {
        ZStack {
          LogsTable(
            lines: model.visibleLines, following: model.isFollowing,
            autosaveName: tableAutosaveName,
            onScroll: { model.personScrolled(atEnd: $0) },
            copyText: { model.copyText(for: $0) })
          if let message = model.emptyMessage {
            Text(message).foregroundStyle(.secondary)
          }
        }
      }
      Divider()
      statusLine
    }
    .toolbar { toolbar }
    .searchable(text: $model.searchText, prompt: "Search")
    .navigationTitle("Logs")
    .alert(
      "Couldn't Save the Logs",
      isPresented: Binding(get: { saveFailure != nil }, set: { _ in saveFailure = nil })
    ) {
      Button("OK") {}
    } message: {
      Text(saveFailure ?? "")
    }
  }

  private var isConnected: Bool { model.phase != .notConnected }

  private var statusLine: some View {
    HStack(spacing: 12) {
      if model.phase != .notConnected {
        Text(model.statusText)
      }
      if let note = model.statusNote {
        Text(note)
      }
      Spacer()
    }
    .font(.callout)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 12)
    .padding(.vertical, 5)
  }

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem {
      Picker("Level", selection: $model.levelFilter) {
        ForEach(LogLevelFilter.allCases) { Text($0.title).tag($0) }
      }
      .pickerStyle(.menu)
      .help("Which levels to show")
      .disabled(!isConnected)
    }
    ToolbarItem {
      Toggle(isOn: $model.isFollowing) {
        Label("Follow", systemImage: "arrow.down.to.line")
      }
      .toggleStyle(.button)
      .help("Keep the newest line in view")
      .disabled(!isConnected)
    }
    ToolbarItem {
      Button("Clear", systemImage: "trash") { model.clear() }
        .help("Clear this window. Umbra's log is not changed.")
        .disabled(!isConnected)
    }
    ToolbarItem {
      Button("Save Logs…", systemImage: "square.and.arrow.down") {
        Task { await save() }
      }
      .help("Save Umbra's log to a file")
      .disabled(!isConnected)
    }
  }

  private func save() async {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = model.suggestedFileName()
    panel.allowedContentTypes = [.plainText]
    panel.canCreateDirectories = true
    panel.message = "Save Umbra's log"
    let response: NSApplication.ModalResponse
    if let window = NSApp.keyWindow {
      response = await panel.beginSheetModal(for: window)
    } else {
      response = panel.runModal()
    }
    guard response == .OK, let url = panel.url else { return }
    do {
      let data = try await model.downloadLogs()
      try data.write(to: url, options: .atomic)
    } catch let error as UmbraError {
      saveFailure = error.message
    } catch {
      saveFailure = error.localizedDescription
    }
  }
}
