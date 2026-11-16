import SwiftUI
import UmbraKit

/// The Add sheet: where the torrent comes from (a .torrent file, or a
/// magnet link or web address typed or pasted), what Umbra says it is, its
/// files with tick boxes, and the choices (category, tags, start paused).
/// Everything it shows and does comes from `AddTorrentModel`.
struct AddSheet: View {
  let model: AddTorrentModel
  /// "412 GB free", shown beside the save folder.
  var freeSpace: String?
  /// Put the cursor in the link field when the sheet opens.
  var focusLink = false
  /// Opens the file panel (nil in pictures of the view).
  var chooseFiles: (() -> Void)?

  @Environment(\.dismiss) private var dismiss
  @FocusState private var linkFocused: Bool

  var body: some View {
    @Bindable var model = model
    VStack(alignment: .leading, spacing: 14) {
      source(link: $model.linkText)
      AddSheetItems(model: model)
      if model.fileTree != nil {
        AddSheetFiles(model: model)
      }
      Divider()
      AddSheetOptions(model: model, freeSpace: freeSpace)
      if let failure = model.addFailure {
        AddSheetNotice(symbol: "xmark.octagon.fill", role: .red, text: failure)
      }
      footer
    }
    .padding(20)
    .frame(width: 520)
    .task { await model.loadFolders() }
    .onAppear { if focusLink { linkFocused = true } }
    .onChange(of: model.isFinished) { _, finished in if finished { dismiss() } }
  }

  /// The link field and the button for files.
  private func source(link: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        TextField(
          "Magnet link or web address", text: link,
          prompt: Text("Paste a magnet link or a .torrent file’s web address")
        )
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .focused($linkFocused)
        .disableAutocorrection(true)
        Button("Choose File…") { chooseFiles?() }
          .help("Choose one or more .torrent files")
      }
      if let note = model.linkNote {
        Text(note)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var footer: some View {
    HStack {
      Spacer()
      Button("Cancel", role: .cancel) { dismiss() }
        .keyboardShortcut(.cancelAction)
      Button(model.addTitle) {
        Task { await model.add() }
      }
      .keyboardShortcut(.defaultAction)
      .disabled(!model.canAdd)
    }
    .controlSize(.large)
  }
}

/// What was chosen, as Umbra describes it: one line per torrent (looking,
/// ready, fetching details, already added or refused).
private struct AddSheetItems: View {
  let model: AddTorrentModel

  var body: some View {
    switch model.items.count {
    case 0:
      Text(
        "Choose a .torrent file, or paste a magnet link or the web address of a .torrent file."
      )
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    case 1:
      AddSheetItemRow(model: model, item: model.items[0], large: true)
    default:
      VStack(alignment: .leading, spacing: 8) {
        ForEach(model.items) { item in
          AddSheetItemRow(model: model, item: item, large: false)
        }
      }
    }
  }
}

private struct AddSheetItemRow: View {
  let model: AddTorrentModel
  let item: AddTorrentModel.Item
  /// The single torrent: a larger icon, and room for the notices.
  let large: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        icon
        VStack(alignment: .leading, spacing: 2) {
          Text(item.name)
            .fontWeight(.semibold)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(item.name)
          detail
        }
        Spacer(minLength: 0)
      }
      if case .waiting = item.state, large {
        // Stand-ins for the file list while it is on its way.
        VStack(alignment: .leading, spacing: 6) {
          ForEach([0.62, 0.48, 0.55], id: \.self) { width in
            RoundedRectangle(cornerRadius: 3)
              .fill(.quaternary)
              .frame(width: 480 * width, height: 9)
          }
        }
        .padding(.leading, large ? 46 : 0)
        .accessibilityHidden(true)
      }
      if case .duplicate = item.state, let text = model.duplicateText {
        duplicateNotice(text)
      }
    }
  }

  @ViewBuilder private var icon: some View {
    let size: CGFloat = large ? 36 : 20
    if item.state == .inspecting {
      ProgressView().controlSize(.small).frame(width: size, height: size)
    } else {
      Image(systemName: symbol)
        .font(large ? .title : .body)
        .foregroundStyle(symbolRole.color)
        .frame(width: size, height: size)
    }
  }

  private var symbol: String {
    switch item.state {
    case .refused: "xmark.octagon.fill"
    case .duplicate: "exclamationmark.triangle.fill"
    case .added: "checkmark.circle.fill"
    default: item.isLink ? "link" : "doc"
    }
  }

  private var symbolRole: ColorRole {
    switch item.state {
    case .refused: .red
    case .duplicate: .orange
    case .added: .green
    default: .accent
    }
  }

  @ViewBuilder private var detail: some View {
    switch item.state {
    case .inspecting:
      secondary("Looking at it…")
    case .waiting:
      secondary(AddTorrentModel.waitingText(item))
    case .ready, .duplicate:
      if let summary = item.summary { secondary(summary).monospacedDigit() }
    case .refused(let message):
      Text(message)
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    case .added:
      secondary("Added")
    }
  }

  private func secondary(_ text: String) -> Text {
    Text(text).font(.callout).foregroundStyle(.secondary)
  }

  private func duplicateNotice(_ text: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("\(Text("Already added.").bold()) \(text)")
        .fixedSize(horizontal: false, vertical: true)
      if let failure = model.trackerFailure {
        Text(failure).font(.callout).foregroundStyle(.red)
      }
      if large {
        HStack {
          Button("Show in List") { model.showExisting() }
          if model.duplicate?.existing.newTrackers.isEmpty == false {
            Button("Add the New Trackers to It") { Task { await model.addTrackersToExisting() } }
              .disabled(model.isAdding)
          }
        }
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
  }
}

/// The single torrent's files, with tick boxes: a folder's box covers
/// everything in it, and shows a dash when only some are ticked.
private struct AddSheetFiles: View {
  let model: AddTorrentModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text("Files").font(.headline)
        Spacer()
        if let summary = model.filesSummary {
          Text(summary).font(.callout).foregroundStyle(.secondary).monospacedDigit()
        }
        Button("Select All") { model.selectAll() }
        Button("Select None") { model.selectNone() }
      }
      .controlSize(.small)
      List(model.visibleNodes) { node in
        AddSheetFileRow(node: node, isClosed: model.collapsed.contains(node.id), model: model)
      }
      .listStyle(.bordered(alternatesRowBackgrounds: true))
      .frame(height: 190)
    }
  }
}

private struct AddSheetFileRow: View {
  let node: FileTree.Node
  let isClosed: Bool
  let model: AddTorrentModel

  var body: some View {
    HStack(spacing: 5) {
      TriStateCheckbox(tick: node.tick, label: "Download \(node.name)") { model.click(node) }
        .fixedSize()
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
        } else {
          Color.clear.frame(width: 12, height: 1)
        }
        Image(systemName: node.isFolder ? "folder" : "doc")
          .foregroundStyle(node.isFolder ? Color.accentColor : .secondary)
        Text(node.name)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(node.id)
      }
      .padding(.leading, CGFloat(node.depth) * 16)
      Spacer(minLength: 8)
      Text(Format.bytes(node.size))
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
    // A file that won't be downloaded fades back.
    .opacity(node.tick == .off ? 0.6 : 1)
  }
}

/// Category, where it is saved, tags and Start paused.
private struct AddSheetOptions: View {
  let model: AddTorrentModel
  let freeSpace: String?
  @State private var newTag = ""

  var body: some View {
    @Bindable var model = model
    VStack(alignment: .leading, spacing: 10) {
      row("Category:") {
        Picker("Category", selection: $model.category) {
          Text("None").tag("")
          if !model.categories.isEmpty { Divider() }
          ForEach(model.categories, id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
      }
      if let folder = model.saveFolder {
        row("Save to:") {
          Image(systemName: "folder").foregroundStyle(.secondary)
          Text(folder).lineLimit(1).truncationMode(.head).help(folder)
          if let freeSpace {
            Text(freeSpace).font(.callout).foregroundStyle(.secondary).fixedSize()
          }
        }
      }
      row("Tags:") { tags }
      row("") {
        Toggle("Start paused", isOn: $model.startPaused)
          .help("Add it, but don’t start downloading yet")
      }
    }
  }

  /// One line of the form: its label on the left, lined up on the right
  /// edge with the others, the Mac's way.
  private func row(_ label: String, @ViewBuilder content: () -> some View) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(label)
        .frame(width: 70, alignment: .trailing)
      content()
      Spacer(minLength: 0)
    }
  }

  /// The chosen tags (click one to take it away), a field for a new one
  /// and a menu of those in use.
  private var tags: some View {
    HStack(spacing: 6) {
      ForEach(model.tags, id: \.self) { tag in
        Button {
          model.removeTag(tag)
        } label: {
          HStack(spacing: 3) {
            Text(tag)
            Image(systemName: "xmark").imageScale(.small)
          }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Remove the tag \(tag)")
        .accessibilityLabel("Remove tag \(tag)")
      }
      TextField("Add tag", text: $newTag)
        .textFieldStyle(.roundedBorder)
        .frame(width: 110)
        .onSubmit(addTyped)
        .onChange(of: newTag) { _, text in if text.hasSuffix(",") { addTyped() } }
      if !model.tagSuggestions.isEmpty {
        Menu {
          ForEach(model.tagSuggestions, id: \.self) { tag in
            Button(tag) { model.addTag(tag) }
          }
        } label: {
          Image(systemName: "tag")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Tags in use")
        .accessibilityLabel("Tags in use")
      }
    }
  }

  private func addTyped() {
    model.addTag(newTag)
    newTag = ""
  }
}

/// A short message with a symbol, inside the sheet.
private struct AddSheetNotice: View {
  let symbol: String
  let role: ColorRole
  let text: String

  var body: some View {
    Label {
      Text(text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
    } icon: {
      Image(systemName: symbol).foregroundStyle(role.color)
    }
  }
}
