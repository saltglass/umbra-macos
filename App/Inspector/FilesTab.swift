import AppKit
import SwiftUI
import UmbraKit

/// Files: the torrent's files as a folder tree, each with a tick box, size,
/// progress and priority. A tick box on a folder covers everything in it.
struct FilesTab: View {
  let model: InspectorModel
  let row: TorrentRow

  var body: some View {
    let fetch = model.files
    VStack(spacing: 0) {
      if let failure = fetch.failure, fetch.value != nil {
        InspectorNotice(text: failure)
          .padding(8)
      }
      if let content = fetch.value {
        if content.tree.isEmpty {
          ContentUnavailableView(
            "Waiting for Details", systemImage: "hourglass",
            description: Text("The files are known once its details arrive."))
        } else {
          summary(content.tree.totals)
          List(content.rows) { node in
            FileRowView(node: node, isClosed: content.collapsed.contains(node.id), model: model)
          }
          .listStyle(.inset)
        }
      } else {
        InspectorFetchState(isLoading: fetch.isLoading, failure: fetch.failure, what: "files")
      }
    }
  }

  /// "214 files · 16.1 GB of 18.4 GB selected"
  private func summary(_ totals: FileTree.Totals) -> some View {
    let files = totals.fileCount == 1 ? "1 file" : "\(Format.count(totals.fileCount)) files"
    let wanted =
      totals.wantedSize == totals.size
      ? Format.bytes(totals.size)
      : "\(Format.bytes(totals.wantedSize)) of \(Format.bytes(totals.size)) selected"
    return Text("\(files) · \(wanted)")
      .font(.callout)
      .foregroundStyle(.secondary)
      .monospacedDigit()
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 6)
  }
}

private struct FileRowView: View {
  let node: FileTree.Node
  /// Whether this folder is shown closed (a closed folder's contents are
  /// simply not in the list).
  let isClosed: Bool
  let model: InspectorModel

  var body: some View {
    HStack(alignment: .top, spacing: 6) {
      TriStateCheckbox(tick: node.tick, label: "Download \(node.name)") {
        Task { await model.click(node) }
      }
      .fixedSize()
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 4) {
          if node.isFolder {
            Button {
              model.toggleFolder(node.id)
            } label: {
              Image(systemName: isClosed ? "chevron.right" : "chevron.down")
                .imageScale(.small)
                .frame(width: 12)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isClosed ? "Open \(node.name)" : "Close \(node.name)")
          }
          Image(systemName: node.isFolder ? "folder" : "doc")
            .foregroundStyle(.secondary)
          Text(node.name)
            .fontWeight(node.isFolder ? .semibold : .regular)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(node.id)
        }
        HStack(spacing: 6) {
          Text("\(Format.bytes(node.size)) · \(Format.percent(node.progress))")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
          ProgressView(value: node.progress)
            .tint(barRole.color)
            .frame(minWidth: 20)
            .accessibilityLabel("Progress of \(node.name)")
          PriorityMenu(node: node, model: model)
        }
      }
    }
    // Each folder level steps in a little.
    .padding(.leading, CGFloat(node.depth) * 14)
    // A file that won't be downloaded fades back.
    .opacity(node.tick == .off ? 0.6 : 1)
    .padding(.vertical, 2)
  }

  private var barRole: ColorRole {
    if node.progress >= 1 { return .green }
    return node.tick == .off ? .secondary : .accent
  }
}

/// Skip, Normal or High for a file, or for all the files in a folder
/// ("Mixed" when they differ).
private struct PriorityMenu: View {
  let node: FileTree.Node
  let model: InspectorModel

  var body: some View {
    Menu {
      Picker(
        "Priority",
        selection: Binding<FileTree.Priority?>(
          get: { node.priority },
          set: { new in
            if let new { Task { await model.choose(new, for: node) } }
          })
      ) {
        ForEach(FileTree.Priority.allCases, id: \.self) { priority in
          Text(priority.label).tag(Optional(priority))
        }
      }
      .pickerStyle(.inline)
    } label: {
      Text(node.priority?.label ?? "Mixed")
        .font(.caption)
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .accessibilityLabel("Priority of \(node.name)")
  }
}

extension FileTree.Priority {
  /// The word Umbra's priority goes by in the menu.
  fileprivate var label: String {
    switch self {
    case .skip: "Skip"
    case .normal: "Normal"
    case .high: "High"
    }
  }
}

/// A real macOS check box that can also show "mixed" (a folder whose files
/// differ); SwiftUI's own Toggle can't. A click doesn't change the box
/// itself: it asks the model, and the box follows what the model then says.
struct TriStateCheckbox: NSViewRepresentable {
  let tick: FileTree.Tick
  let label: String
  let onClick: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSButton {
    let box = NSButton(
      checkboxWithTitle: "", target: context.coordinator, action: #selector(Coordinator.clicked(_:))
    )
    box.allowsMixedState = true
    box.controlSize = .small
    return box
  }

  func updateNSView(_ box: NSButton, context: Context) {
    context.coordinator.onClick = onClick
    context.coordinator.state = Self.state(of: tick)
    box.state = context.coordinator.state
    box.setAccessibilityLabel(label)
  }

  private static func state(of tick: FileTree.Tick) -> NSControl.StateValue {
    switch tick {
    case .on: .on
    case .off: .off
    case .mixed: .mixed
    }
  }

  @MainActor
  final class Coordinator: NSObject {
    var onClick: () -> Void = {}
    /// What the box should show, as the model last said.
    var state = NSControl.StateValue.off

    @objc func clicked(_ box: NSButton) {
      // AppKit has already stepped the box on; put it back until the
      // model's answer comes in.
      box.state = state
      onClick()
    }
  }
}
