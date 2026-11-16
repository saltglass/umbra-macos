import Foundation

extension SettingsFormat where T == Int {
  /// A speed limit that Umbra keeps in KB/s but the page shows in MB/s,
  /// as Umbra's web page does: shown rounded to one decimal (1536 KB/s is
  /// "1.5"), typed with a point or a comma, sent as MB x 1024 rounded to
  /// whole KB/s. Empty means 0, which is no limit, and 0 shows as empty.
  public static func megabytesPerSecond(locale: Locale = .current) -> Self {
    Self(
      text: { kb in
        let mb = (Double(kb) / 1024 * 10).rounded() / 10
        return mb == 0
          ? ""
          : mb.formatted(.number.grouping(.never).precision(.fractionLength(0...1)).locale(locale))
      },
      read: { text in
        let typed = typedNumber(text)
        if typed.blank { return .value(0) }
        guard let mb = typed.number else { return .unreadable }
        return .value(Int((mb * 1024).rounded()))
      })
  }
}
