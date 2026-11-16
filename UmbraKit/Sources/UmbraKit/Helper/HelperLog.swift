import Foundation

/// The helper's log file (`helper.log` in the data folder).
///
/// Umbra writes its log to standard output; the supervisor points that (and
/// standard error) at this file, adding to the end. So it can't grow forever,
/// it is moved aside to `helper.log.1` at start once it passes a size (the
/// older `.1` is dropped). Umbra already hides secrets in what it logs.
struct HelperLog: Sendable {
  let url: URL

  var previousURL: URL {
    url.deletingLastPathComponent().appending(path: url.lastPathComponent + ".1")
  }

  /// Moves the log to `helper.log.1` if it is larger than `limit` bytes.
  func rotate(above limit: Int) {
    let fm = FileManager.default
    let size =
      (try? fm.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? Int) ?? 0
    guard size > limit else { return }
    try? fm.removeItem(at: previousURL)
    try? fm.moveItem(at: url, to: previousURL)
  }

  /// Opens the log for adding to the end, creating it (readable only by
  /// this user) if needed.
  func openForAppending() throws -> FileHandle {
    let path = url.path(percentEncoded: false)
    if !FileManager.default.fileExists(atPath: path) {
      FileManager.default.createFile(
        atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
    }
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    return handle
  }

  /// Adds one line written by the app (not the helper), such as a marker
  /// that it was started again.
  func note(_ line: String) {
    guard let handle = try? openForAppending() else { return }
    try? handle.write(contentsOf: Data("--- \(line) ---\n".utf8))
    try? handle.close()
  }

  /// The last `count` lines of the log (empty if there is none).
  func tail(_ count: Int = 20) -> [String] {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
    defer { try? handle.close() }
    // Reading only the end keeps this quick on a 5 MB log.
    let end = (try? handle.seekToEnd()) ?? 0
    let start = end > 64_000 ? end - 64_000 : 0
    try? handle.seek(toOffset: start)
    let data = (try? handle.readToEnd()) ?? Data()
    let lines = String(decoding: data, as: UTF8.self)
      .split(separator: "\n", omittingEmptySubsequences: true)
      .map(String.init)
    return Array(lines.suffix(count))
  }
}
