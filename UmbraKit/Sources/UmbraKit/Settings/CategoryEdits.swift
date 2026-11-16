import Foundation
import UmbraAPI

/// Changes to the list of categories in Settings → Downloads, as pure
/// edits of the group. Each is handed to the settings model, which applies
/// it to the newest copy Umbra gave, so a category is found by its name
/// (not its position, which another change may have moved).
///
/// Nothing is checked here: a duplicate name or a folder that can't be used
/// is Umbra's refusal to give, and the page shows its words.
public enum CategoryEdits {
  public typealias Downloads = Components.Schemas.DownloadsSettings
  public typealias Category = Components.Schemas.Category

  /// What was typed, without the spaces around it (the web page does the same).
  public static func tidy(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// A new category. An empty folder means "the download folder".
  /// `limits` are its own seed goals and speed limits, if any were set.
  public static func add(
    name: String, folder: String, limits: CategoryLimits? = nil, to value: inout Downloads
  ) {
    var category = Category(name: tidy(name), folder: tidy(folder))
    limits?.apply(to: &category)
    value.categories.append(category)
  }

  /// Renames a category and/or changes its folder. Its seeding goals and
  /// speed limits are kept as they are, unless `limits` replaces them.
  public static func edit(
    _ original: String, name: String, folder: String, limits: CategoryLimits? = nil,
    in value: inout Downloads
  ) {
    guard let i = index(of: original, in: value) else { return }
    value.categories[i].name = tidy(name)
    value.categories[i].folder = tidy(folder)
    limits?.apply(to: &value.categories[i])
  }

  /// Takes a category out. Umbra leaves its torrents with no category.
  public static func remove(_ name: String, from value: inout Downloads) {
    value.categories.removeAll { $0.name == name }
  }

  /// Where a category is in the list now.
  public static func index(of name: String, in value: Downloads) -> Int? {
    value.categories.firstIndex { $0.name == name }
  }

  /// Whether saving the sheet would change nothing.
  public static func isUnchanged(
    _ original: Category, name: String, folder: String, limits: CategoryLimits? = nil
  ) -> Bool {
    original.name == tidy(name) && original.folder == tidy(folder)
      && (limits ?? CategoryLimits(original)) == CategoryLimits(original)
  }
}

/// Umbra's explanation of why it refused a category change, sorted into
/// what the add/edit sheet shows: under the name, under the folder, or as
/// a general line. Umbra names a category's fields by its place in the
/// list ("categories.2.name"), so the sheet says which place is its own.
public struct CategoryProblems: Equatable, Sendable {
  public var name: String?
  public var folder: String?
  /// Under each limit or goal box that Umbra refused.
  public var limits: [LimitField: String] = [:]
  /// Anything else Umbra said: a message with no field, or a field that
  /// isn't this category's.
  public var general: String?

  public var isEmpty: Bool { name == nil && folder == nil && limits.isEmpty && general == nil }

  /// `index` is the category's place in the list that was sent (the end of
  /// the list for a new one).
  public init(_ refusal: UmbraError?, index: Int) {
    guard let refusal else { return }
    if refusal.fields.isEmpty {
      general = refusal.message
      return
    }
    name = refusal.fields["categories.\(index).name"]
    folder = refusal.fields["categories.\(index).folder"]
    var own = Set(["categories.\(index).name", "categories.\(index).folder"])
    for field in LimitField.allCases {
      let key = "categories.\(index).\(field.umbraName)"
      own.insert(key)
      limits[field] = refusal.fields[key]
    }
    let others = refusal.fields
      .filter { !own.contains($0.key) }
      .sorted { $0.key < $1.key }
      .map(\.value)
    if !others.isEmpty { general = others.joined(separator: " ") }
  }
}
