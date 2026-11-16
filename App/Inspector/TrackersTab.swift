import SwiftUI
import UmbraKit

/// Trackers: each address with its tier and how it is doing, and the
/// buttons to add, edit and remove them and to ask them for peers again.
struct TrackersTab: View {
  let model: InspectorModel
  let row: TorrentRow

  @State private var selection: Set<String> = []
  @State private var sheet: TrackerSheet?

  /// Which box is open.
  private enum TrackerSheet: Identifiable {
    case add
    case edit(String)
    var id: String {
      switch self {
      case .add: "add"
      case .edit(let url): "edit \(url)"
      }
    }
  }

  var body: some View {
    let fetch = model.trackers
    VStack(spacing: 0) {
      if let failure = fetch.failure, fetch.value != nil {
        InspectorNotice(text: failure)
          .padding(8)
      }
      if let content = fetch.value {
        if content.rows.isEmpty {
          ContentUnavailableView(
            "No Trackers", systemImage: "antenna.radiowaves.left.and.right.slash",
            description: Text("This torrent has no trackers."))
        } else {
          List(content.rows, selection: $selection) { tracker in
            TrackerRowView(tracker: tracker)
              .tag(tracker.id)
              .contextMenu { menu(for: tracker) }
          }
          .listStyle(.inset)
          .onDeleteCommand { remove(selection) }
          if content.findsPeersElsewhere {
            Text("Peers also found through DHT and peer exchange (public torrents)")
              .font(.caption)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 12)
              .padding(.vertical, 6)
          }
        }
      } else {
        InspectorFetchState(isLoading: fetch.isLoading, failure: fetch.failure, what: "trackers")
      }
      Spacer(minLength: 0)
      Divider()
      buttonBar
    }
    .onChange(of: row.id) { selection = [] }
    // A tracker that has gone (removed, or its address changed) can't stay selected.
    .onChange(of: model.trackers.value?.rows) { _, rows in
      guard let rows else { return }
      selection.formIntersection(rows.map(\.id))
    }
    .sheet(item: $sheet) { sheet in
      switch sheet {
      case .add:
        TrackerAddressSheet(
          title: "Add Trackers", initial: "", multiline: true, saveTitle: "Add",
          help: "One address per line. Each goes in a tier of its own, after the others."
        ) { await model.addTrackers($0) }
      case .edit(let url):
        TrackerAddressSheet(
          title: "Edit Tracker", initial: url, multiline: false, saveTitle: "Save", help: nil
        ) { text in
          let failure = await model.editTracker(url, to: text)
          if failure == nil, let new = InspectorModel.addresses(in: text).first {
            selection = [new]
          }
          return failure
        }
      }
    }
  }

  // MARK: Buttons

  private var buttonBar: some View {
    HStack(spacing: 4) {
      Group {
        Button("Add Tracker", systemImage: "plus") { sheet = .add }
          .help("Add trackers")
        Button("Remove Tracker", systemImage: "minus") { remove(selection) }
          .disabled(selection.isEmpty)
          .help("Remove the selected trackers")
        Button("Edit Tracker", systemImage: "pencil") { editSelected() }
          .disabled(selection.count != 1)
          .help("Change the selected tracker's address")
      }
      .labelStyle(.iconOnly)
      Spacer()
      Button("Ask Again", systemImage: "arrow.clockwise") {
        Task { await model.askAgain() }
      }
      .labelStyle(.titleAndIcon)
      .help("Ask the trackers for peers now")
    }
    .buttonStyle(.borderless)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  @ViewBuilder private func menu(for tracker: TrackerRow) -> some View {
    Button("Edit…") { sheet = .edit(tracker.url) }
    Button("Copy Address") {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(tracker.url, forType: .string)
    }
    Divider()
    // Right-clicking one of several selected acts on all of them, as in Finder.
    Button("Remove", role: .destructive) {
      remove(selection.contains(tracker.id) ? selection : [tracker.id])
    }
  }

  private func editSelected() {
    if selection.count == 1, let url = selection.first { sheet = .edit(url) }
  }

  private func remove(_ urls: Set<String>) {
    guard !urls.isEmpty else { return }
    Task { await model.removeTrackers(urls) }
  }
}

private struct TrackerRowView: View {
  let tracker: TrackerRow

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(tracker.url)
        .font(.system(.caption, design: .monospaced))
        .lineLimit(1)
        .truncationMode(.middle)
      HStack(spacing: 6) {
        Label(tracker.statusText, systemImage: tracker.symbolName)
          .foregroundStyle(tracker.role.color)
        Text(tracker.tierText)
          .foregroundStyle(.secondary)
      }
      .font(.caption)
      if let message = tracker.message {
        Text(message)
          .font(.caption)
          .foregroundStyle(tracker.role.color)
          .fixedSize(horizontal: false, vertical: true)
      }
      if tracker.swarmText != nil || tracker.nextText != nil {
        Text([tracker.swarmText, tracker.nextText].compactMap { $0 }.joined(separator: " · "))
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
    }
    .padding(.vertical, 2)
    .help(tracker.url)
  }
}

/// The small box for adding trackers (several, one per line) or changing
/// one. Umbra's refusal shows inside the box, which stays open.
private struct TrackerAddressSheet: View {
  let title: String
  let initial: String
  let multiline: Bool
  let saveTitle: String
  let help: String?
  /// Sends the text; returns Umbra's words if it refused, nil when it worked.
  let save: (String) async -> String?

  @Environment(\.dismiss) private var dismiss
  @State private var text = ""
  @State private var failure: String?
  @State private var busy = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title).font(.headline)
      if multiline {
        TextEditor(text: $text)
          .font(.system(.body, design: .monospaced))
          .scrollContentBackground(.hidden)
          .padding(4)
          .frame(height: 90)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
      } else {
        TextField("Address", text: $text)
          .font(.system(.body, design: .monospaced))
          .onSubmit(send)
      }
      if let help {
        Text(help).font(.callout).foregroundStyle(.secondary)
      }
      if let failure {
        Label(failure, systemImage: "exclamationmark.triangle.fill")
          .font(.callout)
          .foregroundStyle(ColorRole.red.color)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      }
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button(saveTitle, action: send)
          .keyboardShortcut(.defaultAction)
          .disabled(busy || InspectorModel.addresses(in: text).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 380)
    .onAppear { text = initial }
  }

  private func send() {
    guard !busy, !InspectorModel.addresses(in: text).isEmpty else { return }
    busy = true
    Task {
      let result = await save(text)
      busy = false
      if let result { failure = result } else { dismiss() }
    }
  }
}
