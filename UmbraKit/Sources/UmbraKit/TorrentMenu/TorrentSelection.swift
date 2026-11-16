import Foundation

/// The torrents an action would act on, and the questions the menu, the
/// toolbar and the keyboard ask about them ("can any of these be paused?",
/// "does every one have this tag?"). Umbra decides what an action does;
/// this only decides whether offering it makes sense.
public struct TorrentSelection: Equatable, Sendable {
  /// The selected rows, in the order the list shows them.
  public let rows: [TorrentRow]

  public init(_ rows: [TorrentRow]) {
    self.rows = rows
  }

  public var isEmpty: Bool { rows.isEmpty }
  public var hashes: [String] { rows.map(\.id) }

  /// Pause is offered while at least one of them is not paused already.
  public var canPause: Bool { rows.contains { Self.canPause($0.kind) } }

  /// Whether a torrent in this state can be paused.
  public static func canPause(_ kind: StatusKind) -> Bool { kind != .paused }

  /// Whether a torrent in this state can be resumed.
  public static func canResume(_ kind: StatusKind) -> Bool {
    [.paused, .error, .missingFiles].contains(kind)
  }

  /// Resume is offered while at least one is paused, or stopped by an
  /// error or missing files (Umbra's resume forgets the error and tries again).
  public var canResume: Bool { rows.contains { Self.canResume($0.kind) } }

  /// A torrent still fetching its details (a magnet link) has no .torrent
  /// file to give yet.
  public var canExport: Bool { !isEmpty && !rows.contains { $0.kind == .fetchingDetails } }

  /// What the Space key does: pause what runs, otherwise resume what is
  /// stopped; nothing when neither fits.
  public var spaceAction: TorrentActions.Action? {
    if canPause { return .pause }
    if canResume { return .resume }
    return nil
  }

  /// Whether all, some or none of the torrents are in this category
  /// ("" is "no category").
  public func mark(category: String) -> MenuMark {
    Self.mark(rows.map { $0.category == category })
  }

  /// Whether all, some or none of the torrents have this tag.
  public func mark(tag: String) -> MenuMark {
    Self.mark(rows.map { $0.tags.contains(tag) })
  }

  private static func mark(_ matches: [Bool]) -> MenuMark {
    if matches.isEmpty || !matches.contains(true) { return .off }
    return matches.contains(false) ? .mixed : .on
  }
}
