import Foundation

/// The tracker box on the Create Torrent sheet: one address per line, and
/// a blank line between tiers (the same as Umbra's web page).
///
/// Only the layout is read here. Whether an address is a tracker's is
/// left to Umbra, which says so in its own words under the box.
public enum TrackerText {
  /// The tiers the text holds. Lines are trimmed; blank lines (any number
  /// in a row) end a tier; a tier of nothing is dropped; no blank line at
  /// all means a single tier.
  public static func tiers(from text: String) -> [[String]] {
    var tiers: [[String]] = [[]]
    for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
      let line = raw.trimmingCharacters(in: .whitespaces)
      if line.isEmpty {
        if !tiers[tiers.count - 1].isEmpty { tiers.append([]) }
      } else {
        tiers[tiers.count - 1].append(line)
      }
    }
    return tiers.filter { !$0.isEmpty }
  }
}
