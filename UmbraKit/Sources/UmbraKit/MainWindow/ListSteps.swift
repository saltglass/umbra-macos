import Foundation

/// The smallest-ish set of row changes that turns one list into another,
/// so the window can change only what changed instead of redrawing the
/// whole list every second (which would lose the person's place).
///
/// The steps are in the order AppKit's table applies them: each one's row
/// numbers count the rows as they stand after the steps before it.
public enum ListStep: Equatable, Sendable {
  /// Take these rows out (row numbers in the list as it was).
  case remove(IndexSet)
  /// Put the new list's row in at this position.
  case insert(Int)
  /// Move a row from one position to another.
  case move(from: Int, to: Int)

  /// The steps from `old` to `new` (lists of torrent hashes), or nil when
  /// more than `limit` rows would be inserted or moved: then redrawing the
  /// whole list is quicker and no worse to look at (a re-sort, a new filter).
  public static func steps(from old: [String], to new: [String], limit: Int = 60) -> [ListStep]? {
    if old == new { return [] }
    let wanted = Set(new)
    var steps: [ListStep] = []

    // First take out everything that has gone.
    let gone = IndexSet(old.indices.filter { !wanted.contains(old[$0]) })
    if !gone.isEmpty { steps.append(.remove(gone)) }
    var current = old.enumerated().filter { !gone.contains($0.offset) }.map(\.element)

    // Then walk down the new list, fetching or adding each row where it belongs.
    var work = 0
    for (index, hash) in new.enumerated() {
      if index < current.count, current[index] == hash { continue }
      work += 1
      if work > limit { return nil }
      // Anything above `index` is already in place, so look below it.
      if let from = current[index...].firstIndex(of: hash) {
        current.remove(at: from)
        current.insert(hash, at: index)
        steps.append(.move(from: from, to: index))
      } else {
        current.insert(hash, at: index)
        steps.append(.insert(index))
      }
    }
    return steps
  }

  /// Which row of `new` should be at the top of the view after an update,
  /// when row `top` of `old` was: the row with as many of the remaining
  /// rows above it as before. Rows that only moved (a list sorted by speed)
  /// leave the view where it is; rows that came or went above it are made
  /// up for, so what's on screen stays put. New rows just there go above
  /// the view. Nil when the view was at the very top: it stays there, so
  /// new torrents at the top are seen.
  public static func topRow(old: [String], new: [String], top: Int) -> Int? {
    guard top > 0, top <= old.count, !new.isEmpty else { return nil }
    let staying = Set(new)
    let wereThere = Set(old)
    let above = old[..<top].reduce(0) { $0 + (staying.contains($1) ? 1 : 0) }
    var seen = 0
    for (index, hash) in new.enumerated() where wereThere.contains(hash) {
      if seen == above { return index }
      seen += 1
    }
    return new.count - 1
  }

  /// Applies steps to a list; for checking them (tests) and nothing else.
  public static func apply(_ steps: [ListStep], to list: [String], taking new: [String]) -> [String]
  {
    var list = list
    for step in steps {
      switch step {
      case .remove(let rows):
        for row in rows.reversed() { list.remove(at: row) }
      case .insert(let row):
        list.insert(new[row], at: row)
      case .move(let from, let to):
        let hash = list.remove(at: from)
        list.insert(hash, at: to)
      }
    }
    return list
  }
}
