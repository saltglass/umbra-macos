import Foundation

/// Tells a magnet link from a web address in what the person typed or
/// pasted into the link field, only to know which of Umbra's fields to send it in. Nothing
/// more is read here: Umbra decides whether the link is any good.
public enum AddLink {
  /// What the text in the link field is, the way the web page's Add
  /// dialog reads a line: a magnet link, an http(s) address, or neither.
  public static func input(from text: String) -> TorrentActions.AddInput? {
    let link = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if link.lowercased().hasPrefix("magnet:?") { return .magnet(link) }
    if isWebAddress(link) { return .url(link) }
    return nil
  }

  /// http:// or https:// followed by something, with no spaces in it.
  private static func isWebAddress(_ text: String) -> Bool {
    let lower = text.lowercased()
    guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return false }
    let rest = text.drop(while: { $0 != "/" }).dropFirst(2)
    return !rest.isEmpty && !text.contains(where: \.isWhitespace)
  }
}
