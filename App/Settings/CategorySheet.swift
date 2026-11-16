// The small sheet for adding or editing a download category (Settings →
// Downloads). It stays open when Umbra refuses the change and shows
// Umbra's own words under the field at fault; it closes only once Umbra
// has saved it.

import SwiftUI
import UmbraAPI
import UmbraKit

/// What the sheet is for.
enum CategorySheetKind: Identifiable {
  case add
  case edit(Components.Schemas.Category)

  var id: String {
    switch self {
    case .add: "add"
    case .edit(let category): "edit-\(category.name)"
    }
  }
}

struct CategorySheet: View {
  let kind: CategorySheetKind
  let model: SettingsGroupModel<Components.Schemas.DownloadsSettings>
  /// The global seed goals, for the hints in empty boxes (nil: not shown).
  var seeding: SettingsGroupModel<Components.Schemas.SeedingSettings>?

  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var folder: String
  /// The category's own seed goals and speed limits.
  @State private var limits: LimitsDraft
  /// Waiting for Umbra's answer.
  @State private var saving = false
  @State private var problems: CategoryProblems

  init(
    kind: CategorySheetKind, model: SettingsGroupModel<Components.Schemas.DownloadsSettings>,
    seeding: SettingsGroupModel<Components.Schemas.SeedingSettings>? = nil,
    refusedAs problems: CategoryProblems = CategoryProblems(nil, index: 0)
  ) {
    self.kind = kind
    self.model = model
    self.seeding = seeding
    switch kind {
    case .add:
      _name = State(initialValue: "")
      _folder = State(initialValue: "")
      _limits = State(initialValue: LimitsDraft(category: CategoryLimits()))
    case .edit(let category):
      _name = State(initialValue: category.name)
      _folder = State(initialValue: category.folder)
      _limits = State(initialValue: LimitsDraft(category: CategoryLimits(category)))
    }
    _problems = State(initialValue: problems)
  }

  private var isAdding: Bool {
    if case .add = kind { return true }
    return false
  }

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          TextField("Name", text: $name, prompt: Text("Required"))
            .onSubmit(save)
          SettingsProblem(message: problems.name)
          SettingsFolderRow(
            title: "Folder",
            help: "Where this category's torrents are saved.",
            path: folder, whenEmpty: "The download folder",
            clearTitle: "Use Download Folder",
            panelMessage: "Choose the folder this category saves to.",
            emptyTooltip: "Torrents in this category save to the download folder.",
            problem: problems.folder,
            onChoose: { folder = $0 }, onClear: { folder = "" })
        } footer: {
          Text("Changing a torrent's category doesn't move its files.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        Section {
          ForEach(LimitField.speeds) { limitRow($0) }
        } header: {
          Text("Speed limits")
        } footer: {
          Text("Each torrent in this category. Leave a box empty for no limit of its own.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        Section {
          ForEach(LimitField.goals) { limitRow($0) }
        } header: {
          Text("Seeding goals")
        } footer: {
          VStack(alignment: .leading, spacing: 6) {
            Text(
              "Leave a goal empty to use the global goal (Settings → Queue & Seeding). A "
                + "torrent's own goals come first."
            )
            .foregroundStyle(.secondary)
            SettingsProblem(message: problems.general)
          }
          .font(.callout)
        }
      }
      .formStyle(.grouped)

      HStack {
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button(isAdding ? "Add" : "Save", action: save)
          .keyboardShortcut(.defaultAction)
          // An empty name can't be a category (the web page does the same).
          .disabled(CategoryEdits.tidy(name).isEmpty || saving || !limits.problems.isEmpty)
      }
      .padding([.horizontal, .bottom], 20)
      .padding(.top, 4)
    }
    .frame(width: 520, height: 700)
  }

  /// One limit or goal box. Umbra's refusal shows under it until it is edited.
  private func limitRow(_ field: LimitField) -> some View {
    let hints = LimitHints(global: seeding?.value, forCategory: true)
    return LimitFieldRow(
      field: field, entry: limits[field], placeholder: hints.placeholder(for: field, in: limits),
      problem: problems.limits[field] ?? limits.problems[field], forCategory: true,
      onType: {
        limits.type($0, into: field)
        problems.limits[field] = nil
      },
      onChoose: {
        limits.choose($0, for: field)
        problems.limits[field] = nil
      })
  }

  /// Sends the change and waits for Umbra: closes if it was saved,
  /// otherwise stays and shows why.
  private func save() {
    guard !CategoryEdits.tidy(name).isEmpty, !saving else { return }
    let name = name
    let folder = folder
    let base: CategoryLimits
    if case .edit(let original) = kind {
      base = CategoryLimits(original)
    } else {
      base = CategoryLimits()
    }
    // Nothing half-typed is sent: the boxes say what is wrong.
    guard let newLimits = limits.categoryLimits(base: base) else { return }
    let index: Int
    let change: (inout Components.Schemas.DownloadsSettings) -> Void
    switch kind {
    case .add:
      index = model.value?.categories.count ?? 0
      change = { CategoryEdits.add(name: name, folder: folder, limits: newLimits, to: &$0) }
    case .edit(let original):
      // Nothing was changed: nothing to send.
      if CategoryEdits.isUnchanged(original, name: name, folder: folder, limits: newLimits) {
        dismiss()
        return
      }
      index = model.value.flatMap { CategoryEdits.index(of: original.name, in: $0) } ?? 0
      change = {
        CategoryEdits.edit(
          original.name, name: name, folder: folder, limits: newLimits, in: &$0)
      }
    }
    saving = true
    Task {
      let refusal = await model.changeAndWait(change)
      saving = false
      if refusal == nil {
        dismiss()
      } else {
        problems = CategoryProblems(refusal, index: index)
      }
    }
  }
}
