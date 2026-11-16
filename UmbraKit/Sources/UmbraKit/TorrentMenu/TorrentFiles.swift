import Foundation

/// Where a torrent's files are on this Mac, and what to call its
/// exported .torrent file. (Umbra runs on this Mac, so its paths are ours.)
public enum TorrentFiles {
  /// The torrent's files or folder: its save folder plus its name. The
  /// window falls back to the save folder itself if that is not there yet.
  public static func location(of row: TorrentRow) -> URL {
    URL(fileURLWithPath: row.savePath).appending(path: row.name)
  }

  /// The save folder.
  public static func folder(of row: TorrentRow) -> URL {
    URL(fileURLWithPath: row.savePath, isDirectory: true)
  }

  /// "Name.torrent", safe to use as a file name: slashes and colons (which
  /// Finder shows as slashes) become dashes, and a very long name is cut
  /// to fit the file system's limit.
  public static func exportName(for row: TorrentRow) -> String {
    var name = row.name.map { $0 == "/" || $0 == ":" ? "-" : String($0) }.joined()
    name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if name.isEmpty || name.hasPrefix(".") { name = "Torrent" + name }
    // 255 bytes is the limit; leave room for ".torrent" and a " (2)" suffix.
    while name.utf8.count > 230 { name.removeLast() }
    return name + ".torrent"
  }

  /// `name` unless `taken` has it, otherwise "Name 2.torrent", "Name 3.torrent"...
  public static func uniqueName(_ name: String, taken: Set<String>) -> String {
    guard taken.contains(name) else { return name }
    let base = name.hasSuffix(".torrent") ? String(name.dropLast(".torrent".count)) : name
    var n = 2
    while taken.contains("\(base) \(n).torrent") { n += 1 }
    return "\(base) \(n).torrent"
  }
}
