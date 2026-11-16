// The Limits sheet: one torrent's own speed limits and seed goals, or the
// same for several torrents at once. It stays open when Umbra refuses and
// shows Umbra's own words under the box at fault; it closes only once
// Umbra has saved the change.

import SwiftUI
import UmbraKit

extension View {
  /// Shows the Limits sheet while the window model has a request for it.
  func limitsSheet(window: MainWindowModel, session: AppSession) -> some View {
    modifier(LimitsSheetModifier(window: window, session: session))
  }
}

private struct LimitsSheetModifier: ViewModifier {
  @Bindable var window: MainWindowModel
  let session: AppSession

  func body(content: Content) -> some View {
    content.sheet(item: $window.limitsRequest) { request in
      TorrentLimitsSheet(
        model: TorrentLimitsModel(request: request, actions: { session.actions }),
        onSaved: { window.limitsSaved() })
    }
  }
}

struct TorrentLimitsSheet: View {
  /// Kept for the life of the sheet, so what is typed isn't lost when the
  /// window behind it redraws.
  @State private var model: TorrentLimitsModel
  let onSaved: () -> Void
  @Environment(\.dismiss) private var dismiss

  init(model: TorrentLimitsModel, onSaved: @escaping () -> Void = {}) {
    _model = State(initialValue: model)
    self.onSaved = onSaved
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      content
      buttons
    }
    .frame(width: 520, height: model.isSeveral ? 580 : 540)
    .task { if model.phase == .loading { await model.load() } }
  }

  // MARK: Parts

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(model.heading).font(.title2.weight(.semibold))
      Text(model.subheading)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
      if let note = model.note {
        Text(note)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 2)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding([.horizontal, .top], 20)
    .padding(.bottom, 4)
  }

  @ViewBuilder private var content: some View {
    switch model.phase {
    case .loading:
      ProgressView()
        .controlSize(.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .loadFailed(let message):
      ContentUnavailableView {
        Label("Couldn't Read the Limits", systemImage: "exclamationmark.triangle")
      } description: {
        Text(message)
      } actions: {
        Button("Try Again") { Task { await model.load() } }
      }
    case .ready:
      form
    }
  }

  private var form: some View {
    Form {
      Section("Speed") {
        ForEach(LimitField.speeds) { row($0) }
      }
      Section {
        ForEach(LimitField.goals) { row($0) }
      } header: {
        Text("Seeding goals")
      } footer: {
        VStack(alignment: .leading, spacing: 6) {
          Text(model.footer).foregroundStyle(.secondary)
          SettingsProblem(message: model.generalProblem)
        }
        .font(.callout)
      }
    }
    .formStyle(.grouped)
  }

  private func row(_ field: LimitField) -> some View {
    LimitFieldRow(
      field: field, entry: model.draft[field], placeholder: model.placeholder(for: field),
      problem: model.problem(for: field), several: model.isSeveral,
      onType: { model.type($0, into: field) },
      onChoose: { model.choose($0, for: field) })
  }

  private var buttons: some View {
    HStack {
      if model.saving { ProgressView().controlSize(.small) }
      Spacer()
      Button("Cancel", role: .cancel) { dismiss() }
        .keyboardShortcut(.cancelAction)
      Button("Save") {
        Task {
          if await model.save() {
            onSaved()
            dismiss()
          }
        }
      }
      .keyboardShortcut(.defaultAction)
      .disabled(!model.canSave)
    }
    .padding([.horizontal, .bottom], 20)
    .padding(.top, 4)
  }
}
