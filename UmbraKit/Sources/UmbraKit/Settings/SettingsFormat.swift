import Foundation

/// How a typed field shows a setting as text, and reads typed text back.
///
/// Reading only turns text into a value: whether the value is allowed is
/// Umbra's call. Text that isn't a number at all ("1.2.3", "abc") can't be
/// read, and the field just goes back to the stored value, as on the web
/// page. Whole-number fields round, as the web page does.
public struct SettingsFormat<T>: Sendable {
  /// What reading typed text gave.
  public enum Reading {
    case value(T)
    /// Not something the field can hold (half-typed, or not a number).
    case unreadable
  }

  public let text: @Sendable (T) -> String
  public let read: @Sendable (String) -> Reading

  public init(
    text: @escaping @Sendable (T) -> String, read: @escaping @Sendable (String) -> Reading
  ) {
    self.text = text
    self.read = read
  }
}

// MARK: Numbers

/// A typed number: blank is nil; "1,5" reads as 1.5 whatever the Mac's
/// language, so either way of writing it works.
func typedNumber(_ text: String) -> (blank: Bool, number: Double?) {
  let trimmed = text.trimmingCharacters(in: .whitespaces)
  if trimmed.isEmpty { return (true, nil) }
  guard let number = Double(trimmed.replacing(",", with: ".")), number.isFinite,
    abs(number) < 1e15
  else { return (false, nil) }
  return (false, number)
}

/// A number as a field shows it: up to two decimals, no thousands separator.
func numberText(_ number: Double, locale: Locale) -> String {
  number.formatted(.number.grouping(.never).precision(.fractionLength(0...2)).locale(locale))
}

extension SettingsFormat where T == Int {
  /// A whole number. With `blank`, an empty field means that number and
  /// that number shows as an empty field (for "0 is no limit" settings,
  /// whose field then shows its "No limit" prompt). Without, an empty
  /// field can't be read.
  public static func wholeNumber(blank: Int? = nil) -> Self {
    Self(
      text: { value in value == blank ? "" : String(value) },
      read: { text in
        let typed = typedNumber(text)
        if typed.blank, let blank { return .value(blank) }
        guard let number = typed.number else { return .unreadable }
        return .value(Int(number.rounded()))
      })
  }
}

extension SettingsFormat where T == Int? {
  /// A whole number, or empty for none (nil).
  public static var optionalWholeNumber: Self {
    Self(
      text: { value in value.map(String.init) ?? "" },
      read: { text in
        let typed = typedNumber(text)
        if typed.blank { return .value(nil) }
        guard let number = typed.number else { return .unreadable }
        return .value(Int(number.rounded()))
      })
  }

  /// Minutes, shown and typed as hours (1.5 is 90 minutes), or empty for
  /// none (nil).
  public static func optionalHoursAsMinutes(locale: Locale = .current) -> Self {
    Self(
      text: { value in value.map { numberText(Double($0) / 60, locale: locale) } ?? "" },
      read: { text in
        let typed = typedNumber(text)
        if typed.blank { return .value(nil) }
        guard let hours = typed.number else { return .unreadable }
        return .value(Int((hours * 60).rounded()))
      })
  }
}

extension SettingsFormat where T == Double? {
  /// A number that may have decimals, or empty for none (nil).
  public static func optionalDecimal(locale: Locale = .current) -> Self {
    Self(
      text: { value in value.map { numberText($0, locale: locale) } ?? "" },
      read: { text in
        let typed = typedNumber(text)
        if typed.blank { return .value(nil) }
        guard let number = typed.number else { return .unreadable }
        return .value(number)
      })
  }
}

// MARK: Text

extension SettingsFormat where T == String {
  /// Text as typed (a folder, a host name). Umbra tidies it if it needs to.
  public static var text: Self {
    Self(text: { $0 }, read: { .value($0) })
  }
}

extension SettingsFormat where T == SecretChange {
  /// A new secret (a password). The field always shows empty: the stored
  /// secret is never sent to the Mac. Typing one and committing replaces
  /// it; committing an empty field changes nothing (removing it is a
  /// separate button that sets `.removed`).
  public static var newSecret: Self {
    Self(
      text: { _ in "" },
      read: { text in text.isEmpty ? .value(.unchanged) : .value(.replaced(text)) })
  }
}
