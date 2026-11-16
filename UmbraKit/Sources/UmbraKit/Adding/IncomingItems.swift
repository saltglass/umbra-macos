import Foundation

/// Things that arrive from outside the app and should open the Add sheet:
/// .torrent files (double-clicked in Finder, dropped on the Dock icon or on
/// the window) and magnet links (clicked in a browser, or dropped).
///
/// This sorts what arrives and holds it until the sheet can open. Umbra may
/// not be connected yet (the app was started by the file itself), or a
/// sheet may already be open. Nothing is ever added from here: it only
/// decides what the next sheet shows. The person always sees the sheet and
/// presses Add.
///
/// Only `.torrent` files and `magnet:` links are accepted. Web addresses
/// (http, https) and every other kind of file are ignored.
public struct IncomingItems: Equatable, Sendable {
  /// One thing that arrived.
  public enum Item: Equatable, Sendable {
    case torrentFile(URL)
    case magnet(String)
  }

  /// What one sheet should open with.
  public enum Batch: Equatable, Sendable {
    /// All the files waiting, together in one sheet.
    case files([URL])
    /// One magnet link.
    case magnet(String)
  }

  private var files: [URL] = []
  private var magnets: [String] = []

  public init() {}

  /// Nothing is waiting.
  public var isEmpty: Bool { files.isEmpty && magnets.isEmpty }

  // MARK: Sorting what arrives

  /// A .torrent file (any capitals in the ending) or a magnet link; nil
  /// for anything else.
  public static func classify(_ url: URL) -> Item? {
    if url.isFileURL {
      return url.pathExtension.lowercased() == "torrent" ? .torrentFile(url) : nil
    }
    guard url.scheme?.lowercased() == "magnet" else { return nil }
    return magnet(url.absoluteString)
  }

  /// Dropped or pasted text: magnet links, one per line, and file
  /// addresses ("file:///…") of .torrent files. Anything else is ignored.
  public static func classify(text: String) -> [Item] {
    text.split(whereSeparator: \.isNewline).compactMap { line in
      let piece = line.trimmingCharacters(in: .whitespaces)
      if let link = magnet(piece) { return link }
      if piece.lowercased().hasPrefix("file:"), let url = URL(string: piece) {
        return classify(url)
      }
      return nil
    }
  }

  private static func magnet(_ text: String) -> Item? {
    if case .magnet(let link) = AddLink.input(from: text) { return .magnet(link) }
    return nil
  }

  // MARK: Holding

  /// Keeps what is wanted from these. True if anything was.
  @discardableResult
  public mutating func add(urls: [URL]) -> Bool {
    add(urls.compactMap { Self.classify($0) })
  }

  /// Keeps what is wanted from dropped text. True if anything was.
  @discardableResult
  public mutating func add(text: String) -> Bool {
    add(Self.classify(text: text))
  }

  /// A file or link already waiting is not kept twice.
  private mutating func add(_ items: [Item]) -> Bool {
    for item in items {
      switch item {
      case .torrentFile(let url):
        let key = url.standardizedFileURL.path
        if !files.contains(where: { $0.standardizedFileURL.path == key }) { files.append(url) }
      case .magnet(let link):
        if !magnets.contains(link) { magnets.append(link) }
      }
    }
    return !items.isEmpty
  }

  /// The next sheet's worth, or nil when nothing waits or `ready` is false
  /// (Umbra isn't connected, or a sheet is open). All the waiting files go
  /// in one batch, first; then each magnet link gets its own.
  public mutating func nextBatch(ready: Bool) -> Batch? {
    guard ready else { return nil }
    if !files.isEmpty {
      defer { files = [] }
      return .files(files)
    }
    if !magnets.isEmpty { return .magnet(magnets.removeFirst()) }
    return nil
  }
}
