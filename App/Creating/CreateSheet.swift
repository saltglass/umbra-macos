import SwiftUI
import UmbraAPI
import UmbraKit

/// The Create Torrent sheet: what to share, the options, then Create and
/// its progress. Everything it shows and does comes from `CreateTorrentModel`.
struct CreateSheet: View {
  let model: CreateTorrentModel
  /// The live feed's list of torrents being made.
  var creations: [Components.Schemas.Creation]?
  /// Opens the file panel (nil in pictures of the view).
  var chooseItem: (() -> Void)?
  /// Opens the save panel (nil in pictures of the view).
  var saveFile: (() -> Void)?

  @Environment(\.dismiss) private var dismiss
  @State private var dropTargeted = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      CreateSheetSource(model: model, targeted: dropTargeted, chooseItem: chooseItem)
      Divider()
      CreateSheetOptions(model: model)
        .disabled(!model.isEditable)
      CreateSheetStatus(model: model)
      if let failure = model.generalFailure {
        CreateSheetNotice(symbol: "xmark.octagon.fill", role: .red, text: failure)
      }
      if let failure = model.saveFailure {
        CreateSheetNotice(symbol: "xmark.octagon.fill", role: .red, text: failure)
      }
      footer
    }
    .padding(20)
    .frame(width: 520)
    .dropDestination(for: URL.self) { urls, _ in
      guard model.isEditable, let url = urls.first(where: \.isFileURL) else { return false }
      model.choose(url: url)
      return true
    } isTargeted: {
      dropTargeted = $0
    }
    .onChange(of: creations) { _, list in model.receive(creations: list) }
  }

  // MARK: Buttons

  @ViewBuilder private var footer: some View {
    HStack {
      switch model.phase {
      case .done:
        Button("Save .torrent File…") { saveFile?() }
          .disabled(model.isSaving)
        Spacer()
        Button("Done") { dismiss() }
          .keyboardShortcut(.cancelAction)
          .keyboardShortcut(.defaultAction)
      case .failed, .gone:
        Spacer()
        Button("Close", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Try Again") { Task { await model.tryAgain() } }
          .keyboardShortcut(.defaultAction)
      case .queued, .reading:
        Spacer()
        Button("Cancel", role: .cancel) { cancel() }
          .keyboardShortcut(.cancelAction)
      case .editing, .starting:
        Spacer()
        Button("Cancel", role: .cancel) { cancel() }
          .keyboardShortcut(.cancelAction)
        Button("Create") { Task { await model.create() } }
          .keyboardShortcut(.defaultAction)
          .disabled(!model.canCreate)
      }
    }
    .controlSize(.large)
  }

  private func cancel() {
    Task {
      await model.cancel()
      dismiss()
    }
  }
}

// MARK: What to share

/// The chosen file or folder, as Umbra describes it, with the button for
/// the open panel. A file or folder can also be dropped on the sheet.
private struct CreateSheetSource: View {
  let model: CreateTorrentModel
  let targeted: Bool
  let chooseItem: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("What to share").font(.headline)
      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .center, spacing: 10) {
          icon
          VStack(alignment: .leading, spacing: 2) { detail }
          Spacer(minLength: 8)
          Button("Choose File or Folder…") { chooseItem?() }
            .disabled(!model.isEditable)
        }
        if let summary = model.previewSummary {
          // Under the row, so it has the whole width.
          Text(summary).font(.callout).foregroundStyle(.secondary).monospacedDigit()
            .padding(.leading, 42)
        }
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(Color.accentColor, lineWidth: 2)
          .opacity(targeted ? 1 : 0)
      }
      if let problem = model.pathProblem {
        Label {
          Text(problem).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        } icon: {
          Image(systemName: "xmark.octagon.fill").foregroundStyle(ColorRole.red.color)
        }
        .font(.callout)
      }
    }
  }

  @ViewBuilder private var icon: some View {
    switch model.previewState {
    case .looking:
      ProgressView().controlSize(.small).frame(width: 32, height: 32)
    case .none:
      Image(systemName: "square.and.arrow.down.on.square")
        .font(.title)
        .foregroundStyle(.secondary)
        .frame(width: 32, height: 32)
    case .ready, .refused:
      Image(systemName: isFolder ? "folder.fill" : "doc.fill")
        .font(.title)
        .foregroundStyle(
          model.pathProblem == nil ? ColorRole.accent.color : ColorRole.secondary.color
        )
        .frame(width: 32, height: 32)
    }
  }

  private var isFolder: Bool {
    var directory: ObjCBool = false
    if FileManager.default.fileExists(atPath: model.path, isDirectory: &directory) {
      return directory.boolValue
    }
    if case .ready(let preview) = model.previewState { return preview.files > 1 }
    return false
  }

  @ViewBuilder private var detail: some View {
    if model.path.isEmpty {
      Text("Choose a file or folder on this Mac, or drop one here.")
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    } else {
      Text(model.chosenName)
        .fontWeight(.semibold)
        .lineLimit(1)
        .truncationMode(.middle)
        .help(model.path)
      switch model.previewState {
      case .looking:
        Text("Looking at it…").font(.callout).foregroundStyle(.secondary)
      case .ready:
        Text(model.path)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.head)
          .help(model.path)
      case .none, .refused:
        Text(model.path)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.head)
          .help(model.path)
      }
    }
  }
}

// MARK: Options

/// Only the choices Umbra has: trackers, private, comment, source, piece
/// size and whether to start seeding.
private struct CreateSheetOptions: View {
  let model: CreateTorrentModel

  var body: some View {
    @Bindable var model = model
    VStack(alignment: .leading, spacing: 10) {
      row("Trackers:", field: .trackers, top: true) {
        TextEditor(text: $model.trackersText)
          .font(.system(.callout, design: .monospaced))
          .scrollContentBackground(.hidden)
          .autocorrectionDisabled()
          .padding(3)
          .frame(height: 66)
          .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
          .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator))
          .accessibilityLabel("Trackers")
        note("One address per line. A blank line starts a new tier.")
      }
      row("", field: nil) {
        Toggle("Private torrent", isOn: $model.isPrivate)
        note("Peers come only from its trackers, never the DHT or peer exchange.")
      }
      row("Comment:", field: .comment) {
        TextField("Comment", text: $model.comment)
          .labelsHidden()
          .textFieldStyle(.roundedBorder)
      }
      row("Source:", field: .source) {
        TextField("Source", text: $model.source, prompt: Text("Only if your tracker asks for one"))
          .labelsHidden()
          .textFieldStyle(.roundedBorder)
      }
      row("Piece size:", field: .pieceLength) {
        Picker("Piece size", selection: $model.pieceSize) {
          Text("Automatic").tag(CreateTorrentModel.PieceSize.automatic)
          Divider()
          ForEach(CreateTorrentModel.PieceSize.all) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
        note("Automatic suits nearly everything.")
      }
      Divider()
      row("", field: nil) {
        Toggle("Start seeding when created", isOn: $model.startSeeding)
        if model.startSeeding {
          note(CreateTorrentModel.seedingNote)
        }
      }
    }
  }

  /// One line of the form: its label on the left, lined up on the right
  /// edge with the others, and the field's refusal (Umbra's words) under it.
  private func row(
    _ label: String, field: CreateTorrentModel.Field?, top: Bool = false,
    @ViewBuilder content: () -> some View
  ) -> some View {
    HStack(alignment: top ? .top : .firstTextBaseline, spacing: 8) {
      Text(label)
        .frame(width: 80, alignment: .trailing)
        .padding(.top, top ? 4 : 0)
      VStack(alignment: .leading, spacing: 4) {
        content()
        if let field, let problem = model.problem(field), field != .path {
          Label {
            Text(problem).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
          } icon: {
            Image(systemName: "xmark.octagon.fill").foregroundStyle(ColorRole.red.color)
          }
          .font(.callout)
        }
      }
    }
  }

  private func note(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }
}

// MARK: Progress and result

/// The bar while Umbra reads the files, and what happened when it stops.
private struct CreateSheetStatus: View {
  let model: CreateTorrentModel

  var body: some View {
    switch model.phase {
    case .editing:
      EmptyView()
    case .starting, .queued, .reading:
      VStack(alignment: .leading, spacing: 6) {
        if let fraction = model.fraction {
          ProgressView(value: fraction)
        } else {
          ProgressView().progressViewStyle(.linear)
        }
        Text(model.progressLine)
          .font(.callout)
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .fixedSize(horizontal: false, vertical: true)
      }
    case .done:
      VStack(alignment: .leading, spacing: 8) {
        Label {
          Text("Torrent made").fontWeight(.semibold)
        } icon: {
          Image(systemName: "checkmark.circle.fill").foregroundStyle(ColorRole.green.color)
        }
        if let summary = model.madeSummary {
          Text(summary).font(.callout).foregroundStyle(.secondary).monospacedDigit()
        }
        if model.isSeeding, let path = model.creation?.path {
          Text("It’s in the list, seeding from \(path).")
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }
        if let problem = model.seedingProblem {
          CreateSheetNotice(
            symbol: "exclamationmark.triangle.fill", role: .orange,
            text: "Umbra made the torrent but couldn’t start seeding it: \(problem)")
        }
      }
    case .failed(let words):
      VStack(alignment: .leading, spacing: 4) {
        Label {
          Text("Couldn’t make the torrent").fontWeight(.semibold)
        } icon: {
          Image(systemName: "xmark.octagon.fill").foregroundStyle(ColorRole.red.color)
        }
        // Umbra's own words, with a capital letter to start the sentence.
        Text(words.prefix(1).uppercased() + words.dropFirst())
          .font(.callout)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      }
    case .gone:
      CreateSheetNotice(
        symbol: "exclamationmark.triangle.fill", role: .orange,
        text: "This torrent isn’t being made any more (dismissed, or Umbra restarted).")
    }
  }
}

/// A short message with a symbol, inside the sheet.
private struct CreateSheetNotice: View {
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
