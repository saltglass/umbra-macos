// Two more building blocks for settings pages (the shared ones live in
// SettingsParts.swift): a typed text field, and the way a page reaches
// Umbra for a one-off request such as "Send a Test".

import SwiftUI
import UmbraKit

/// A typed text field in a settings form (a mail server, an address): the
/// label and its explanation on the left, the box on the right, and
/// Umbra's message under the label when it refused this field.
///
/// Like the number box, what is typed is sent only on Return or on leaving
/// the box. With `secret`, the box hides what's typed, and (given
/// `.newSecret`) empties as soon as it has been sent: the stored value
/// is never shown, because Umbra never sends it.
struct SettingsTextRow<Value: Equatable & Sendable, T: Equatable>: View {
  let title: String
  var help: String?
  let model: SettingsGroupModel<Value>
  let field: WritableKeyPath<Value, T>
  /// Umbra's name for the field, which its refusals use.
  let umbraName: String
  let format: SettingsFormat<T>
  /// Shown in the box when it's empty.
  var prompt: String?
  var secret = false
  var width: CGFloat = 220

  @FocusState private var focused: Bool

  var body: some View {
    LabeledContent {
      box
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .frame(width: width)
        .focused($focused)
        .onSubmit { model.commit(field, as: format) }
    } label: {
      Text(title)
      if let help { Text(help) }
      SettingsProblem(message: model.problem(for: umbraName))
    }
    .onChange(of: focused) { _, isFocused in
      if !isFocused { model.commit(field, as: format) }
    }
    .onDisappear { model.commit(field, as: format) }
  }

  private var text: Binding<String> {
    Binding(
      get: { model.text(field, as: format) },
      set: { model.type($0, into: field) })
  }

  @ViewBuilder private var box: some View {
    if secret {
      SecureField(title, text: text, prompt: prompt.map { Text($0) })
    } else {
      TextField(title, text: text, prompt: prompt.map { Text($0) })
        // Addresses and server names: no capital letters or corrections.
        .autocorrectionDisabled()
    }
  }
}

// MARK: Reaching Umbra from a page

private struct SettingsSourceKey: EnvironmentKey {
  // Computed, so no shared mutable state is involved.
  static var defaultValue: (any SettingsSource)? { nil }
}

extension EnvironmentValues {
  /// Where the app's connection to Umbra comes from (the running app sets
  /// it; pictures and previews don't, and have none). Pages that make a
  /// one-off request, such as sending a test email, use it; ordinary
  /// settings go through their group's model instead.
  var settingsSource: (any SettingsSource)? {
    get { self[SettingsSourceKey.self] }
    set { self[SettingsSourceKey.self] = newValue }
  }
}
