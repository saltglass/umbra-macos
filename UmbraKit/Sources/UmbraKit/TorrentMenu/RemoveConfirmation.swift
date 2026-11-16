import Foundation

/// The words of the Remove alert and the hashes it is about. Nothing is
/// ever removed without this alert: the window shows it, and only its
/// Remove button sends the request.
public struct RemoveConfirmation: Equatable, Sendable {
  /// The torrents to remove, fixed when the alert opens so a change in the
  /// list while it is open can't change what it removes.
  public let hashes: [String]
  /// "Remove “Name”?" or "Remove 3 torrents?"
  public let title: String
  /// What Remove does when the box is not ticked.
  public let message: String
  /// The tick box's words, with how much would be deleted.
  public let deleteFilesLabel: String
  /// What Remove does when the box is ticked, plainly: Umbra deletes the
  /// files itself, so they never reach the Trash.
  public let deleteMessage: String
  /// How many of the torrents Umbra made from the person's own files
  /// (Create Torrent, seeded from where they are). Their files are the
  /// person's originals, not a download, and the alert says so.
  public let ownFilesCount: Int

  public let removeButton = "Remove"
  public let cancelButton = "Cancel"

  /// Nil when nothing is selected.
  public init?(_ selection: TorrentSelection) {
    let rows = selection.rows
    guard let first = rows.first else { return nil }
    hashes = selection.hashes
    let one = rows.count == 1
    let own = rows.filter(\.madeFromOwnFiles).count
    ownFilesCount = own
    title = one ? "Remove “\(first.name)”?" : "Remove \(Format.count(rows.count)) torrents?"

    // A torrent made from the person's own files has no "downloaded
    // files": it has their originals. One more sentence says so.
    let ownNote: String? =
      switch (one, own) {
      case (_, 0): nil
      case (true, _): "“\(first.name)” was made from your own files. Deleting them can't be undone."
      case (false, rows.count):
        "All of these were made from your own files. Deleting them can't be undone."
      default:
        "\(Format.count(own)) of these were made from your own files. Deleting those can't be undone."
      }
    let files =
      own == 0
      ? (one ? "its downloaded files" : "their downloaded files")
      : (one ? "its files" : "their files")
    let stay =
      own == 0
      ? "The downloaded files stay on your Mac."
      : (one ? "Its files stay on your Mac." : "Their files stay on your Mac.")
    let keep =
      one
      ? "Umbra stops sharing it and removes it from the list. \(stay)"
      : "Umbra stops sharing them and removes them from the list. \(stay)"
    let delete =
      one
      ? "Umbra removes it from the list and deletes \(files) for good. They don't go to the Trash, so they can't be recovered."
      : "Umbra removes them from the list and deletes \(files) for good. They don't go to the Trash, so they can't be recovered."
    message = [keep, ownNote].compactMap { $0 }.joined(separator: "\n\n")
    deleteMessage = [delete, ownNote].compactMap { $0 }.joined(separator: "\n\n")

    // What is on the disk: the part of each torrent downloaded so far,
    // as the web page counts it. A torrent with nothing yet shows no figure.
    let onDisk = rows.reduce(0.0) { $0 + Double($1.size) * $1.progress }
    let figure = onDisk >= 1 ? " (\(Format.bytes(onDisk)))" : ""
    deleteFilesLabel =
      switch (one, own) {
      case (_, 0): "Also delete the downloaded files\(figure)"
      case (true, _):
        "Also delete its files\(figure): these are your original files, not a download"
      default: "Also delete their files\(figure)"
      }
  }

  /// The alert's text under its title, for the box's current state.
  public func message(deletingFiles: Bool) -> String {
    deletingFiles ? deleteMessage : message
  }

  /// The destructive button's words, for the box's current state. With the
  /// box ticked and one of the person's own torrents among them, it says
  /// outright that files are deleted.
  public func removeButton(deletingFiles: Bool) -> String {
    deletingFiles && ownFilesCount > 0 ? "Remove and Delete Files" : removeButton
  }
}
