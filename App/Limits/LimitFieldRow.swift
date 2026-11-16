// One limit or goal in a form: its label and what it means, a box for the
// number with its unit, and a small menu for the other choices (leave it
// as it is, use the default, no goal). Used by the Limits sheet and by the
// category sheet, so both look and behave alike.

import SwiftUI
import UmbraKit

struct LimitFieldRow: View {
  let field: LimitField
  let entry: LimitEntry
  /// The grey hint in an empty box: what applies, or "Leave as it is".
  let placeholder: String
  /// Umbra's words (or "Enter a number.") under the label.
  let problem: String?
  /// Several torrents: "Leave as it is" is a choice, and an empty box is that choice.
  var several = false
  /// A category's sheet: the words say "category", not "torrent".
  var forCategory = false
  let onType: (String) -> Void
  let onChoose: (LimitsDraft.Choice) -> Void

  /// Single speeds need no menu: an empty box already means "no limit of its own".
  private var showsMenu: Bool { several || field.isGoal }

  var body: some View {
    LabeledContent {
      HStack(spacing: 6) {
        TextField(
          field.title,
          text: Binding(get: { entry.text }, set: { onType($0) }),
          prompt: Text(placeholder)
        )
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
        .frame(width: 150)
        Text(field.unit ?? "")
          .foregroundStyle(.secondary)
          .frame(width: 40, alignment: .leading)
        if showsMenu { menu } else { Color.clear.frame(width: 22, height: 1) }
      }
    } label: {
      Text(field.title)
      Text(field.help)
      SettingsProblem(message: problem)
    }
  }

  // MARK: The menu

  private var menu: some View {
    Menu {
      if several {
        choice("Leave as it is", .leave, selected: !entry.touched && entry.mode == .own)
      }
      choice(
        defaultTitle, .useDefault,
        selected: entry.mode == .useDefault
          || (!several && entry.mode == .own && entry.touched
            && entry.text.trimmingCharacters(in: .whitespaces).isEmpty)
      )
      if field.isGoal {
        choice(
          forCategory ? "No goal for this category" : "No goal for this torrent", .noGoal,
          selected: entry.mode == .noGoal)
      }
    } label: {
      Image(systemName: "chevron.down.circle")
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .frame(width: 22)
    .help("Other choices for \(field.title.lowercased())")
    .accessibilityLabel("Other choices for \(field.title)")
  }

  private var defaultTitle: String {
    if forCategory { return field.isGoal ? "Use the global goal" : "No limit" }
    return field.isGoal ? "Use the category's or global goal" : "No limit of its own"
  }

  private func choice(_ title: String, _ choice: LimitsDraft.Choice, selected: Bool)
    -> some View
  {
    Button {
      onChoose(choice)
    } label: {
      if selected { Label(title, systemImage: "checkmark") } else { Text(title) }
    }
  }
}
