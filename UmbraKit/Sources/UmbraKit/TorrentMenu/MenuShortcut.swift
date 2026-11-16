/// A keyboard shortcut on a menu item, described without any Mac menu
/// types so it can be tested: always ⌘ plus, optionally, ⇧ and ⌥.
public struct MenuShortcut: Equatable, Sendable {
  public enum Key: Equatable, Sendable {
    /// A letter, digit or punctuation key, in lower case.
    case character(Character)
    /// The Delete key (⌫).
    case delete
  }

  public let key: Key
  public let shift: Bool
  public let option: Bool

  public init(_ key: Key, shift: Bool = false, option: Bool = false) {
    self.key = key
    self.shift = shift
    self.option = option
  }

  public init(_ character: Character, shift: Bool = false, option: Bool = false) {
    self.init(.character(character), shift: shift, option: option)
  }

  /// The shortcut as a menu shows it, in the Mac's order: "⇧⌘C".
  public var display: String {
    let letter: String
    switch key {
    case .character(let c): letter = String(c).uppercased()
    case .delete: letter = "⌫"
    }
    return (option ? "⌥" : "") + (shift ? "⇧" : "") + "⌘" + letter
  }
}
