// The building blocks every settings page uses, so all pages look and
// behave alike. See README.md in this folder for how to add a page.

import SwiftUI
import UmbraKit

/// A settings page's frame: a grouped form, the way macOS's own settings
/// look, once every group the page shows is loaded; until then a plain
/// "not connected", "loading" or "couldn't read" state instead.
struct SettingsForm<Content: View>: View {
  /// Every group the page shows.
  let groups: [any SettingsGroupStatus]
  @ViewBuilder let content: Content

  var body: some View {
    Group {
      switch SettingsPhase.combined(groups.map(\.phase)) {
      case .loaded:
        Form { content }
          .formStyle(.grouped)
      case .loading:
        ProgressView()
          .controlSize(.small)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .notConnected:
        ContentUnavailableView(
          "Umbra Isn't Running", systemImage: "bolt.horizontal.circle",
          description: Text("Settings can be changed once Umbra has started."))
      case .loadFailed(let message):
        ContentUnavailableView {
          Label("Couldn't Read These Settings", systemImage: "exclamationmark.triangle")
        } description: {
          Text(message)
        } actions: {
          Button("Try Again") {
            for group in groups { group.retry() }
          }
        }
      }
    }
    .frame(width: SettingsMetrics.width)
    .frame(minHeight: 260, idealHeight: SettingsMetrics.height)
  }
}

enum SettingsMetrics {
  /// Every page is this wide, so switching pages doesn't jump sideways.
  static let width: CGFloat = 560
  static let height: CGFloat = 460
  /// General has the most sections.
  static let generalHeight: CGFloat = 720
}

/// A typed number field in a settings form: the label and its explanation
/// on the left, the box (and its unit) on the right, and Umbra's message
/// under the label when it refused this field.
///
/// What is typed is sent only on Return or on leaving the box (also when
/// the page or window closes); a value Umbra refuses goes back by itself.
struct SettingsNumberRow<Value: Equatable & Sendable, T: Equatable>: View {
  let title: String
  /// One line saying what the setting does (the web page's wording).
  var help: String?
  let model: SettingsGroupModel<Value>
  let field: WritableKeyPath<Value, T>
  /// Umbra's name for the field ("maxActiveDownloads"), which its
  /// refusals use to say which field is at fault.
  let umbraName: String
  let format: SettingsFormat<T>
  /// Shown in the box when it's empty ("No limit", "No goal").
  var prompt: String?
  /// After the box ("hours", "min").
  var unit: String?

  @FocusState private var focused: Bool

  var body: some View {
    LabeledContent {
      HStack(spacing: 6) {
        TextField(
          title,
          text: Binding(
            get: { model.text(field, as: format) },
            set: { model.type($0, into: field) }),
          prompt: prompt.map { Text($0) }
        )
        .labelsHidden()
        // A grouped form draws text fields without a box; numbers read
        // better in one, as in System Settings.
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
        .frame(width: 80)
        .focused($focused)
        .onSubmit { model.commit(field, as: format) }
        // Always as wide, so the boxes on a page line up, unit or not.
        Text(unit ?? "")
          .foregroundStyle(.secondary)
          .frame(width: 40, alignment: .leading)
      }
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
}

/// A switch in a settings form; it's sent the moment it's flipped.
struct SettingsToggleRow<Value: Equatable & Sendable>: View {
  let title: String
  var help: String?
  let model: SettingsGroupModel<Value>
  let field: WritableKeyPath<Value, Bool>
  let umbraName: String

  var body: some View {
    Toggle(isOn: model.binding(field, otherwise: false)) {
      Text(title)
      if let help { Text(help) }
      SettingsProblem(message: model.problem(for: umbraName))
    }
  }
}

/// Umbra's explanation of a refusal, in the system's red, or nothing.
struct SettingsProblem: View {
  let message: String?

  var body: some View {
    if let message {
      Label(message, systemImage: "exclamationmark.circle.fill")
        .foregroundStyle(.red)
    }
  }
}

extension SettingsGroupModel {
  /// A binding for a switch or a menu: reads what the page shows, and
  /// sends a change the moment it's made. `otherwise` is shown before the
  /// group is loaded (the form isn't drawn then anyway).
  func binding<T>(_ field: WritableKeyPath<Value, T>, otherwise: T) -> Binding<T> {
    Binding(
      get: { self.value?[keyPath: field] ?? otherwise },
      set: { self.set(field, to: $0) })
  }
}
