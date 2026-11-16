import Foundation

extension SettingsFormat where T == Int? {
  /// A whole number for a setting Umbra may leave out (nil) but where an
  /// empty box must still say something: an empty box means `blank` (0 for
  /// "0 is off") and both `blank` and nil show as an empty box, so the
  /// field's "Off" or "No limit" prompt appears.
  ///
  /// Not the same as `optionalWholeNumber`, where empty is nil: a setting
  /// that is nil is "left out", which makes Umbra keep its old value, so
  /// emptying the box would never turn the setting off.
  public static func wholeNumber(blank: Int) -> Self {
    Self(
      text: { value in value == nil || value == blank ? "" : String(value ?? blank) },
      read: { text in
        let typed = typedNumber(text)
        if typed.blank { return .value(blank) }
        guard let number = typed.number else { return .unreadable }
        return .value(Int(number.rounded()))
      })
  }
}
