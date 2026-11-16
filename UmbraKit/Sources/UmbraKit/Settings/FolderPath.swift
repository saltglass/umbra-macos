import Foundation

/// How a folder is written on screen.
public enum FolderPath {
  /// The Mac way: the home folder as `~` ("/Users/alex/Movies" shows as
  /// "~/Movies"). Anything else is left as it is. The full path belongs in
  /// a tooltip.
  public static func abbreviated(_ path: String, home: String = NSHomeDirectory()) -> String {
    let home = home.hasSuffix("/") && home.count > 1 ? String(home.dropLast()) : home
    guard !home.isEmpty, home != "/" else { return path }
    if path == home { return "~" }
    if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
    return path
  }
}
