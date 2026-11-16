import Foundation

/// Selecting a torrent the Add sheet just added (or found already there).
///
/// Umbra answers "added" before the live feed brings the new row, so the
/// selection waits for the row to arrive, for up to `selectionWait`. If the
/// sidebar or the search would hide it, the list goes back to All with no
/// search, so the person sees what they just added.
extension MainWindowModel {
  /// How long to wait for an added torrent to appear in the list.
  static let selectionWait: TimeInterval = 10

  /// Selects these torrents now if the list has them, or as soon as it does.
  public func selectWhenListed(_ hashes: [String]) {
    guard !hashes.isEmpty else { return }
    pendingSelection = (hashes, now().addingTimeInterval(Self.selectionWait))
    selectPendingIfListed()
  }

  /// Called each time the rows are remade: selects what is waiting to be
  /// selected once every one of them is in the list (or, when the wait is
  /// over, whichever are).
  func selectPendingIfListed() {
    guard let pending = pendingSelection else { return }
    let listed = Set(allRows.map(\.id))
    let present = pending.hashes.filter { listed.contains($0) }
    let timedOut = now() >= pending.until
    guard present.count == pending.hashes.count || timedOut else { return }
    pendingSelection = nil
    guard !present.isEmpty else { return }
    let shown = Set(visibleRows.map(\.id))
    if present.contains(where: { !shown.contains($0) }) {
      // The filter or the search hides it: show everything.
      searchText = ""
      filter = .all
    }
    selection = Set(present)
  }
}
