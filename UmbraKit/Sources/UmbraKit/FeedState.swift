import Foundation
import UmbraAPI

/// Whether the live feed is open.
public enum FeedConnectionState: Sendable, Equatable {
  /// Opening for the first time (or stopped).
  case connecting
  /// Open: updates are arriving.
  case live
  /// It dropped at `since` and is retrying. The list shown is the last one received.
  case reconnecting(since: Date)
  /// The server turned our credential away (401 or 403). The feed has
  /// stopped for good; only a new connection (a new credential) can help.
  case refused
}

/// Something that happened to the feed, for `FeedState.apply`.
public enum FeedInput: Sendable, Equatable {
  /// The server answered and the stream is open.
  case opened
  /// A message arrived.
  case event(FeedEvent)
  /// The stream broke or ended at this time; it will be retried.
  case dropped(at: Date)
  /// The server turned the credential away; the feed has stopped.
  case refused
}

/// Something the owner of a `FeedState` must do after applying an input.
/// (The state itself only does arithmetic; anything that talks to the
/// network or the person is handed back as one of these.)
public enum FeedEffect: Sendable, Equatable {
  /// A delta didn't follow on from our list: something was missed, so the
  /// whole list must be fetched again (GET /torrents).
  case refetch
  /// A download finished: tell the person.
  case finished(Components.Schemas.TorrentFinished)
  /// A settings group changed: anything showing it should fetch it again.
  case settingsChanged(group: String)
}

/// The live torrent list and everything else the feed carries, and the rules
/// for bringing it up to date.
///
/// This is a Swift copy of the web app's `web/src/hooks/feed.ts` (the `Feed`
/// class's `snapshot`, `delta`, `patch` and event handlers), kept exactly
/// in step with it:
///
/// - A snapshot replaces the whole list and sets the revision number.
/// - A delta applies only on top of the revision it follows (its `from` is
///   our `rev`). One up to a revision we already have is skipped: a new
///   stream's snapshot is followed by the change that snapshot already took.
///   Anything else means an update was missed, and the list is fetched again.
///
/// It is a plain value with no networking, so it can be tested exhaustively.
public struct FeedState: Sendable, Equatable {
  /// Every torrent, in the order the web app keeps them: the snapshot's
  /// order, with torrents added later at the end. A changed torrent keeps
  /// its place. (The web app keeps them in a JavaScript `Map`, which
  /// remembers the order keys were first put in; this does the same.)
  public private(set) var torrents: [Components.Schemas.Torrent] = []
  /// Where each torrent is in `torrents`, by hash, for quick lookup.
  private var positions: [String: Int] = [:]
  /// The revision of the list held; deltas name the revision they follow.
  public private(set) var rev: Int64 = 0
  /// False until the first snapshot arrives.
  public private(set) var loaded = false
  /// Totals for the status bar, including the VPN state.
  public var transfer: Components.Schemas.Transfer?
  /// Torrents being made, once the server has sent them.
  public var creations: [Components.Schemas.Creation]?
  /// Whether the stream is open.
  public var connection: FeedConnectionState = .connecting
  /// True from the moment the stream opens until its first snapshot
  /// arrives. The list held until then is the one from before the stream
  /// dropped, so it is not yet a fair picture of Umbra's torrents.
  public private(set) var awaitingSnapshot = false

  public init() {}

  /// The torrent with this hash, if it is in the list.
  public func torrent(hash: String) -> Components.Schemas.Torrent? {
    positions[hash].map { torrents[$0] }
  }

  /// Brings the state up to date with one input, and says what else to do.
  public mutating func apply(_ input: FeedInput) -> [FeedEffect] {
    switch input {
    case .opened:
      connection = .live
      awaitingSnapshot = true
    case .refused:
      connection = .refused
    case .dropped(let date):
      // Keep the time of the first drop while retries keep failing, so
      // "reconnecting since" means since the feed was last working.
      if case .reconnecting = connection { break }
      connection = .reconnecting(since: date)
    case .event(let event):
      return apply(event)
    }
    return []
  }

  private mutating func apply(_ event: FeedEvent) -> [FeedEffect] {
    switch event {
    case .snapshot(let snapshot):
      applySnapshot(snapshot)
    case .delta(let delta):
      if applyDelta(delta) == .missed { return [.refetch] }
    case .transfer(let transfer):
      self.transfer = transfer
    case .creations(let list):
      creations = list
    case .finished(let finished):
      return [.finished(finished)]
    case .settingsChanged(let group):
      return [.settingsChanged(group: group)]
    }
    return []
  }

  /// Replaces the whole list (feed.ts `snapshot`).
  public mutating func applySnapshot(_ snapshot: Components.Schemas.TorrentsSnapshot) {
    torrents = []
    positions = [:]
    put(snapshot.torrents)
    rev = snapshot.rev
    loaded = true
    awaitingSnapshot = false
  }

  /// What `applyDelta` did.
  public enum DeltaOutcome: Sendable, Equatable {
    case applied
    /// The list already includes it; nothing changed.
    case alreadyHave
    /// It doesn't follow on from our list; nothing changed, refetch.
    case missed
  }

  /// Applies a delta (feed.ts `delta`).
  @discardableResult
  public mutating func applyDelta(_ delta: Components.Schemas.TorrentsDelta) -> DeltaOutcome {
    if delta.rev <= rev { return .alreadyHave }
    if delta.from != rev { return .missed }
    // Changes first, then removals, as feed.ts does: a torrent in both ends up removed.
    put(delta.changed)
    remove(delta.removed)
    rev = delta.rev
    return .applied
  }

  /// Puts fresh rows in at once, without changing the revision (feed.ts
  /// `patch`): after an action, so the list answers before the next delta.
  public mutating func patch(_ rows: [Components.Schemas.Torrent]) {
    put(rows)
  }

  /// Sets each row: in its existing place if the hash is known, otherwise at the end.
  private mutating func put(_ rows: [Components.Schemas.Torrent]) {
    for row in rows {
      if let position = positions[row.hash] {
        torrents[position] = row
      } else {
        positions[row.hash] = torrents.count
        torrents.append(row)
      }
    }
  }

  /// Takes out the torrents with these hashes, keeping the others' order.
  private mutating func remove(_ hashes: [String]) {
    let gone = Set(hashes.filter { positions[$0] != nil })
    guard !gone.isEmpty else { return }
    // One pass over the list, however many go: it may hold thousands.
    torrents.removeAll { gone.contains($0.hash) }
    positions = Dictionary(
      uniqueKeysWithValues: torrents.enumerated().map { ($0.element.hash, $0.offset) })
  }
}
