import SwiftUI
import UmbraKit

/// The panel beside the list: what the selected torrent is, in four tabs.
/// With nothing or several torrents selected it says so instead.
struct InspectorView: View {
  @Bindable var model: InspectorModel

  var body: some View {
    Group {
      switch model.subject {
      case .none:
        ContentUnavailableView(
          "No selection", systemImage: "info.circle",
          description: Text("Select a torrent to see its details."))
      case .several(let summary):
        ContentUnavailableView {
          Label(summary.title, systemImage: "square.stack")
        } description: {
          Text(summary.detail)
            .monospacedDigit()
          Text("Select a single torrent to see its details.")
        }
      case .one(let row):
        OneTorrentInspector(model: model, row: row)
      }
    }
    // Fetching for the visible tab lives and dies with this: SwiftUI
    // restarts it when the torrent, the tab or the inspector's being open
    // changes, and `watch` is nil when nothing should be fetched.
    .task(id: model.watch) {
      if let watch = model.watch { await model.run(watch) }
    }
    // The torrent's own limits (General tab): read when another torrent is
    // selected and again after a Limits sheet is saved.
    .task(id: model.limitsKey) {
      await model.loadLimits()
    }
  }
}

/// The torrent's name and status, the tab picker, and the tab.
private struct OneTorrentInspector: View {
  @Bindable var model: InspectorModel
  let row: TorrentRow

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 4) {
        Text(row.name)
          .font(.headline)
          .lineLimit(3)
          .truncationMode(.middle)
          .textSelection(.enabled)
        Label(row.statusLabel, systemImage: row.kind.symbolName)
          .font(.subheadline)
          .foregroundStyle(row.kind.textRole.color)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.top, 12)

      Picker("Inspector tab", selection: $model.tab) {
        ForEach(InspectorModel.Tab.allCases) { Text($0.title).tag($0) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .padding(.horizontal, 16)
      .padding(.vertical, 10)

      if let failure = model.changeFailure {
        InspectorNotice(text: failure, onDismiss: { model.dismissChangeFailure() })
          .padding(.horizontal, 12)
          .padding(.bottom, 8)
      }

      Divider()

      switch model.tab {
      case .general: GeneralTab(model: model, row: row)
      case .trackers: TrackersTab(model: model, row: row)
      case .peers: PeersTab(model: model, row: row)
      case .files: FilesTab(model: model, row: row)
      }
    }
  }
}

/// A line in the inspector saying something went wrong, in Umbra's words.
struct InspectorNotice: View {
  let text: String
  var onDismiss: (() -> Void)?

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(ColorRole.red.color)
      Text(text)
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
      if let onDismiss {
        Button(action: onDismiss) {
          Image(systemName: "xmark")
        }
        .buttonStyle(.borderless)
        .help("Dismiss")
        .accessibilityLabel("Dismiss")
      }
    }
    .padding(8)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
  }
}

/// What a fetched tab shows while it has nothing to list: a spinner, or
/// Umbra's explanation of why the fetch failed.
struct InspectorFetchState: View {
  let isLoading: Bool
  let failure: String?
  /// "trackers", "peers" or "files": "Couldn't load the trackers".
  let what: String

  var body: some View {
    if let failure {
      ContentUnavailableView(
        "Couldn't load the \(what)", systemImage: "exclamationmark.triangle",
        description: Text(failure))
    } else if isLoading {
      ProgressView()
        .controlSize(.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}
