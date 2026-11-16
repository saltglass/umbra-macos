// Settings → Downloads: where torrents are saved, the folders Umbra
// watches, how much disk to keep free, and the categories. One of Umbra's
// groups ("downloads"). Wording and units follow Umbra's web page
// (web/src/pages/settings/BasicPages.tsx); Umbra checks every value
// (a folder that can't be used, a duplicate category name) and says why it
// refuses one.

import SwiftUI
import UmbraAPI
import UmbraKit

struct DownloadsPage: View {
  typealias Settings = Components.Schemas.DownloadsSettings

  let downloads: SettingsGroupModel<Settings>
  /// The global seed goals, shown as hints in the category sheet's empty boxes.
  var seeding: SettingsGroupModel<Components.Schemas.SeedingSettings>?

  /// The category picked in the list, by name.
  @State private var selection: String?
  @State private var sheet: CategorySheetKind?
  /// The category waiting for "Remove" to be confirmed.
  @State private var removing: String?
  /// Umbra's words when it refused a removal.
  @State private var removeProblem: String?

  var body: some View {
    SettingsForm(groups: [downloads]) {
      Section {
        SettingsFolderRow(
          title: "Save downloads to",
          help: "Where torrents are saved unless their category says otherwise.",
          path: downloads.value?.folder ?? "",
          // When Umbra's own folder is empty it uses this default one.
          whenEmpty: downloads.value?.defaultFolder ?? "The default folder",
          clearTitle: "Use Default",
          panelMessage: "Choose the folder downloads are saved to.",
          dimWhenEmpty: false,
          emptyTooltip: "The default folder, in use until you choose another.",
          problem: downloads.problem(for: "folder"),
          onChoose: { downloads.set(\.folder, to: $0) },
          onClear: { downloads.set(\.folder, to: "") })
        SettingsFolderRow(
          title: "Keep unfinished downloads in",
          help:
            "Optional. Downloads stay here until they finish, then move to their folder. "
            + "Off: they download straight into their folder.",
          path: downloads.value?.incompleteFolder ?? "",
          whenEmpty: "Off", clearTitle: "Turn Off",
          panelMessage: "Choose the folder unfinished downloads are kept in.",
          problem: downloads.problem(for: "incompleteFolder"),
          onChoose: { downloads.set(\.incompleteFolder, to: $0) },
          onClear: { downloads.set(\.incompleteFolder, to: "") })
        SettingsFolderRow(
          title: "Watch a folder for .torrent files",
          help:
            ".torrent and .magnet files put here are added and started; in a subfolder "
            + "named after a category, with that category. Each is then renamed to end in "
            + ".added, or .failed if it couldn't be added (the log says why).",
          path: downloads.value?.watchFolder ?? "",
          whenEmpty: "Off", clearTitle: "Turn Off",
          panelMessage: "Choose the folder to watch for .torrent files.",
          problem: downloads.problem(for: "watchFolder"),
          // "" turns it off; leaving it out would keep the old folder.
          onChoose: { downloads.set(\.watchFolder, to: $0) },
          onClear: { downloads.set(\.watchFolder, to: "") })
      } header: {
        Text("Folders")
      } footer: {
        SettingsProblem(message: downloads.pageProblem)
          .font(.callout)
      }

      Section {
        SettingsNumberRow(
          title: "Keep this much disk space free",
          help:
            "Below this, a banner warns you, and downloads that would go below it wait until "
            + "there's room (each download folder's disk is checked). 0 turns both off.",
          model: downloads, field: \.lowSpaceWarningGB, umbraName: "lowSpaceWarningGB",
          format: .wholeNumber(blank: 0), prompt: "Off", unit: "GB")
      } header: {
        Text("Free space")
      }

      Section {
        categoryList
      } header: {
        Text("Categories")
      } footer: {
        VStack(alignment: .leading, spacing: 6) {
          Text(
            "Each category saves to its own folder. Changing a torrent's category doesn't "
              + "move its files."
          )
          .foregroundStyle(.secondary)
          SettingsProblem(message: removeProblem)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .sheet(item: $sheet) { kind in
      CategorySheet(kind: kind, model: downloads, seeding: seeding)
    }
    .confirmationDialog(
      "Remove the category “\(removing ?? "")”?",
      isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
      titleVisibility: .visible
    ) {
      Button("Remove", role: .destructive) {
        if let name = removing { remove(name) }
      }
    } message: {
      // What Umbra does (internal/torrents/rules.go: RemoveCategories).
      Text(
        "Its torrents stay in the list but are left with no category. Their files stay where they are."
      )
    }
  }

  private var categories: [Components.Schemas.Category] {
    downloads.value?.categories ?? []
  }

  /// The list with its + and − and Edit… under it, as the system's own
  /// settings lists have them. Double-click, or Return, edits.
  private var categoryList: some View {
    VStack(spacing: 6) {
      List(selection: $selection) {
        ForEach(categories, id: \.name) { category in
          HStack {
            Text(category.name)
              .lineLimit(1)
            Spacer(minLength: 12)
            Text(
              category.folder.isEmpty
                ? "The download folder" : FolderPath.abbreviated(category.folder)
            )
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
          }
          .help(category.folder.isEmpty ? "Saves to the download folder." : category.folder)
          .tag(category.name)
        }
      }
      .listStyle(.bordered(alternatesRowBackgrounds: true))
      .frame(height: max(88, min(CGFloat(categories.count) * 24 + 4, 200)))
      .overlay {
        if categories.isEmpty {
          Text("No categories")
            .foregroundStyle(.secondary)
        }
      }
      .contextMenu(forSelectionType: String.self) { names in
        if let name = names.first {
          Button("Edit…") { edit(name) }
          Button("Remove…", role: .destructive) { askToRemove(name) }
        }
      } primaryAction: { names in
        if let name = names.first { edit(name) }
      }
      .onDeleteCommand {
        if let selection { askToRemove(selection) }
      }

      HStack(spacing: 4) {
        Button("Add Category", systemImage: "plus") { sheet = .add }
        Button("Remove Category", systemImage: "minus") {
          if let selection { askToRemove(selection) }
        }
        .disabled(selection == nil)
        Spacer()
        Button("Edit…") {
          if let selection { edit(selection) }
        }
        .disabled(selection == nil)
      }
      .labelStyle(.iconOnly)
      // The + and − are small square buttons; "Edit…" keeps its words.
      .buttonStyle(.bordered)
      .controlSize(.small)
    }
  }

  private func edit(_ name: String) {
    guard let category = categories.first(where: { $0.name == name }) else { return }
    sheet = .edit(category)
  }

  private func askToRemove(_ name: String) {
    removing = name
  }

  private func remove(_ name: String) {
    removeProblem = nil
    selection = nil
    Task {
      let refusal = await downloads.changeAndWait { CategoryEdits.remove(name, from: &$0) }
      removeProblem = CategoryProblems(refusal, index: -1).general
    }
  }
}
