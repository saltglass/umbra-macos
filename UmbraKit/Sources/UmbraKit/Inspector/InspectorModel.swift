import Foundation
import Observation
import UmbraAPI

/// What the inspector (the panel beside the list) shows, and the rules for
/// when it asks Umbra for more.
///
/// One torrent selected: its name and status, and four tabs. General is
/// worked out from the torrent already in the list (the live feed keeps it
/// fresh). Trackers, Peers and Files are fetched from Umbra, and only while
/// that tab is on screen, the inspector is open and exactly one torrent is
/// selected; they are fetched again on the web page's schedule (trackers
/// every 5 seconds, peers 2, files 3) and stop the moment any of that stops
/// being true.
///
/// A fetch that fails keeps Umbra's own words in the tab. A change that
/// fails (editing trackers, ticking files) puts Umbra's words in
/// `changeFailure`, shown as a line in the inspector, not as an alert.
@MainActor @Observable
public final class InspectorModel {
  public enum Tab: String, CaseIterable, Identifiable, Sendable {
    case general, trackers, peers, files

    public var id: String { rawValue }

    public var title: String {
      switch self {
      case .general: "General"
      case .trackers: "Trackers"
      case .peers: "Peers"
      case .files: "Files"
      }
    }

    /// How often the tab asks again while it is on screen (the web page's
    /// own timing); nil for General, which asks for nothing.
    public var refreshInterval: Duration? {
      switch self {
      case .general: nil
      case .trackers: .seconds(5)
      case .peers: .seconds(2)
      case .files: .seconds(3)
      }
    }
  }

  /// What is being asked for right now: which torrent and which tab.
  public struct Watch: Hashable, Sendable {
    public let hash: String
    public let tab: Tab
  }

  /// What the inspector is about.
  public enum Subject: Equatable, Sendable {
    case none
    case one(TorrentRow)
    case several(SelectionSummary)
  }

  /// A tab's contents as last fetched: nothing yet, what arrived, and/or
  /// why the last fetch failed (the old contents stay beside the reason).
  public struct Fetch<Value: Equatable & Sendable>: Equatable, Sendable {
    public var value: Value?
    public var failure: String?
    /// Nothing has come back yet, one way or the other.
    public var isLoading: Bool { value == nil && failure == nil }
  }

  /// The Trackers tab's contents.
  public struct TrackersContent: Equatable, Sendable {
    public var rows: [TrackerRow]
    /// Peers are also found through the DHT or peer exchange.
    public var findsPeersElsewhere: Bool
  }

  /// The Files tab's contents: the tree, and the rows to draw.
  public struct FilesContent: Equatable, Sendable {
    public var tree: FileTree
    /// The folders the person has closed.
    public var collapsed: Set<String>
    /// The tree's lines minus what is inside closed folders.
    public var rows: [FileTree.Node]

    init(tree: FileTree, collapsed: Set<String>) {
      self.tree = tree
      self.collapsed = collapsed
      rows = tree.visibleNodes(collapsed: collapsed)
    }
  }

  // MARK: What the person has chosen

  /// The tab showing. Switching clears an old "couldn't change" line.
  public var tab: Tab = .general {
    didSet { if tab != oldValue { changeFailure = nil } }
  }

  /// Umbra's words for the last change that failed, for a line in the
  /// inspector; nil when none, or once dismissed.
  public private(set) var changeFailure: String?

  public func dismissChangeFailure() { changeFailure = nil }

  // MARK: What the inspector shows

  /// Nothing, one torrent (as a list row) or a summary of several.
  public var subject: Subject {
    let rows = window.visibleRows.filter { window.selection.contains($0.id) }
    switch rows.count {
    case 0: return .none
    case 1: return .one(rows[0])
    default: return .several(SelectionSummary(rows))
    }
  }

  /// The hash of the one selected torrent; nil for none or several.
  public var selectedHash: String? {
    guard window.selection.count == 1 else { return nil }
    return window.selectedHashes.first
  }

  /// What should be fetched now, or nil when nothing should: the tab must
  /// be one that fetches, the inspector open, exactly one torrent
  /// selected and Umbra connected. The view runs `run(_:)` for this and
  /// restarts it whenever it changes, which is what stops the fetching.
  public var watch: Watch? {
    guard window.inspectorShown, tab.refreshInterval != nil, connected,
      let hash = selectedHash
    else { return nil }
    return Watch(hash: hash, tab: tab)
  }

  /// Whether Umbra is connected (changes can be sent).
  public var connected: Bool { actions() != nil }

  /// The trackers of the selected torrent.
  public var trackers: Fetch<TrackersContent> { current(trackersStored) }
  /// The peers of the selected torrent, busiest first.
  public var peers: Fetch<[PeerRow]> { current(peersStored) }
  /// The files of the selected torrent.
  public var files: Fetch<FilesContent> { current(filesStored) }

  // MARK: The torrent's own limits (General tab)

  /// The own limits of the selected torrent, for rows in General.
  public var limits: Fetch<LimitsSummary> { current(limitsStored) }

  /// What General must be fetched for: the one selected torrent, and how
  /// many times a Limits sheet has been saved (which changes them).
  public struct LimitsKey: Hashable, Sendable {
    public let hash: String?
    public let saves: Int
    public let connected: Bool
  }

  public var limitsKey: LimitsKey {
    LimitsKey(hash: selectedHash, saves: window.limitsSaves, connected: connected)
  }

  /// Reads the selected torrent's own limits once. General shows them
  /// when they arrive; they are read again after a Limits sheet is saved.
  public func loadLimits() async {
    guard let hash = selectedHash, let actions = actions() else { return }
    do {
      let own = try await actions.limits(of: hash).own
      keep(LimitsSummary(own), for: hash, in: \.limitsStored)
    } catch {
      keepFailure(error.message, for: hash, in: \.limitsStored)
    }
  }

  /// "Edit…": opens the Limits sheet for the selected torrent.
  public func editLimits() { window.showLimits() }

  // MARK: Setting up

  /// How to wait (tests pass one that doesn't really wait).
  public typealias Sleep = @Sendable (Duration) async throws -> Void

  private let window: MainWindowModel
  @ObservationIgnored private let actions: @MainActor () -> TorrentActions?
  @ObservationIgnored private let now: @MainActor () -> Date
  @ObservationIgnored private let sleep: Sleep

  /// What was fetched for one torrent. Kept with its hash so that what
  /// arrives for a torrent no longer selected is never shown for another.
  private struct Stored<Value: Equatable & Sendable>: Equatable {
    var hash: String
    var fetch: Fetch<Value>
  }
  private var trackersStored: Stored<TrackersContent>?
  private var peersStored: Stored<[PeerRow]>?
  private var filesStored: Stored<FilesContent>?
  private var limitsStored: Stored<LimitsSummary>?
  /// The folders closed for the torrent whose files are shown.
  @ObservationIgnored private var closedFolders: (hash: String, folders: Set<String>) = ("", [])

  /// - Parameters:
  ///   - window: the main window's model (selection and whether the inspector is open).
  ///   - actions: Umbra's calls; nil while not connected. A closure so the
  ///     model follows reconnections.
  public init(
    window: MainWindowModel,
    actions: @escaping @MainActor () -> TorrentActions?,
    now: @escaping @MainActor () -> Date = { Date() },
    sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
  ) {
    self.window = window
    self.actions = actions
    self.now = now
    self.sleep = sleep
  }

  private func current<Value>(_ stored: Stored<Value>?) -> Fetch<Value> {
    guard let stored, stored.hash == selectedHash else { return Fetch() }
    return stored.fetch
  }

  // MARK: Fixed contents (pictures of the views)

  /// Fills the tabs with fixed contents for `hash`, as if just fetched,
  /// without asking Umbra. For pictures of the views and previews only.
  public func showFixture(
    for hash: String, trackers: [Components.Schemas.Tracker] = [],
    findsPeersElsewhere: Bool = false, peers: [Components.Schemas.Peer] = [],
    files: [FileTree.File] = [], limits: Components.Schemas.OwnLimits? = nil
  ) {
    let date = now()
    trackersStored = Stored(
      hash: hash,
      fetch: Fetch(
        value: TrackersContent(
          rows: trackers.map { TrackerRow($0, now: date) },
          findsPeersElsewhere: findsPeersElsewhere), failure: nil))
    peersStored = Stored(hash: hash, fetch: Fetch(value: PeerRow.rows(peers), failure: nil))
    filesStored = Stored(
      hash: hash,
      fetch: Fetch(
        value: FilesContent(tree: FileTree(files: files), collapsed: closed(for: hash)),
        failure: nil))
    limitsStored = limits.map {
      Stored(hash: hash, fetch: Fetch(value: LimitsSummary($0), failure: nil))
    }
  }

  // MARK: Fetching

  /// Fetches for `target`, then again after its tab's interval, until the
  /// task running this is cancelled.
  public func run(_ target: Watch) async {
    while !Task.isCancelled {
      await refresh(target)
      guard let interval = target.tab.refreshInterval else { return }
      do {
        try await sleep(interval)
      } catch {
        return
      }
    }
  }

  /// Fetches the target's tab once and keeps the answer (or Umbra's
  /// explanation of why not).
  func refresh(_ target: Watch) async {
    guard let actions = actions() else { return }
    switch target.tab {
    case .general:
      return
    case .trackers:
      do {
        let list = try await actions.trackers(of: target.hash)
        let date = now()
        let content = TrackersContent(
          rows: list.trackers.map { TrackerRow($0, now: date) },
          findsPeersElsewhere: list.dht || list.pex)
        keep(content, for: target.hash, in: \.trackersStored)
      } catch {
        keepFailure(error.message, for: target.hash, in: \.trackersStored)
      }
    case .peers:
      do {
        let list = try await actions.peers(of: target.hash)
        keep(PeerRow.rows(list), for: target.hash, in: \.peersStored)
      } catch {
        keepFailure(error.message, for: target.hash, in: \.peersStored)
      }
    case .files:
      do {
        let list = try await actions.files(of: target.hash)
        keepFiles(list, for: target.hash)
      } catch {
        keepFailure(error.message, for: target.hash, in: \.filesStored)
      }
    }
  }

  private func keep<Value: Equatable & Sendable>(
    _ value: Value, for hash: String,
    in slot: ReferenceWritableKeyPath<InspectorModel, Stored<Value>?>
  ) {
    // A late answer for a torrent no longer selected is thrown away.
    guard !Task.isCancelled, hash == selectedHash else { return }
    let stored = Stored(hash: hash, fetch: Fetch(value: value, failure: nil))
    if self[keyPath: slot] != stored { self[keyPath: slot] = stored }
  }

  private func keepFailure<Value: Equatable & Sendable>(
    _ message: String, for hash: String,
    in slot: ReferenceWritableKeyPath<InspectorModel, Stored<Value>?>
  ) {
    guard !Task.isCancelled, hash == selectedHash else { return }
    // Keep what was there before, if it was for this torrent.
    let before = self[keyPath: slot].flatMap { $0.hash == hash ? $0.fetch.value : nil }
    let stored = Stored(hash: hash, fetch: Fetch<Value>(value: before, failure: message))
    if self[keyPath: slot] != stored { self[keyPath: slot] = stored }
  }

  private func keepFiles(_ list: [FileTree.File], for hash: String) {
    guard !Task.isCancelled, hash == selectedHash else { return }
    let before = filesStored.flatMap { $0.hash == hash ? $0.fetch.value : nil }
    // The tree keeps its shape when only progress moved, so most fetches
    // cost one pass over the files and no redraw of the folders.
    let tree = before?.tree.updating(with: list) ?? FileTree(files: list)
    let content = FilesContent(tree: tree, collapsed: closed(for: hash))
    if let before, before == content {
      // Nothing changed; still clears an old failure.
      if filesStored?.fetch.failure != nil {
        filesStored = Stored(hash: hash, fetch: Fetch(value: before, failure: nil))
      }
      return
    }
    filesStored = Stored(hash: hash, fetch: Fetch(value: content, failure: nil))
  }

  // MARK: Folders

  private func closed(for hash: String) -> Set<String> {
    closedFolders.hash == hash ? closedFolders.folders : []
  }

  /// Opens or closes a folder in the Files tab.
  public func toggleFolder(_ id: String) {
    guard let hash = selectedHash, let stored = filesStored, stored.hash == hash,
      var content = stored.fetch.value
    else { return }
    var folders = closed(for: hash)
    if folders.contains(id) { folders.remove(id) } else { folders.insert(id) }
    closedFolders = (hash, folders)
    content = FilesContent(tree: content.tree, collapsed: folders)
    filesStored = Stored(hash: hash, fetch: Fetch(value: content, failure: stored.fetch.failure))
  }

  // MARK: Changing files

  /// Ticks or unticks a file or folder.
  public func click(_ node: FileTree.Node) async {
    guard let tree = files.value?.tree else { return }
    await setPriorities(tree.changesForClick(on: node))
  }

  /// Gives a file, or every file in a folder, a priority.
  public func choose(_ priority: FileTree.Priority, for node: FileTree.Node) async {
    guard let tree = files.value?.tree else { return }
    await setPriorities(tree.changes(priority: priority, for: node))
  }

  /// Sends priority changes (file index to priority). The tree shows them
  /// at once; Umbra's answer, fetched straight after, is what stays.
  func setPriorities(_ changes: [Int: FileTree.Priority]) async {
    guard !changes.isEmpty, let hash = selectedHash, let actions = actions(),
      let stored = filesStored, stored.hash == hash, let content = stored.fetch.value
    else { return }
    let shown = FilesContent(tree: content.tree.applying(changes), collapsed: content.collapsed)
    filesStored = Stored(hash: hash, fetch: Fetch(value: shown, failure: stored.fetch.failure))
    do {
      try await actions.setFilePriorities(changes, of: hash)
      changeFailure = nil
    } catch {
      changeFailure = error.message
    }
    // Either way, what Umbra says now is the truth.
    await refresh(Watch(hash: hash, tab: .files))
  }

  // MARK: Changing trackers

  /// The addresses in a box with one per line: trimmed, blanks dropped.
  public static func addresses(in text: String) -> [String] {
    text.split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  /// Adds the addresses in `text` (one per line). Returns Umbra's words if
  /// it refused, for the box that is asking to show; nil when it worked.
  public func addTrackers(_ text: String) async -> String? {
    let urls = Self.addresses(in: text)
    guard !urls.isEmpty else { return "Enter a tracker address." }
    return await change { actions, hash in try await actions.addTrackers(urls, to: hash) }
  }

  /// Changes one tracker's address to the first one in `text`.
  public func editTracker(_ old: String, to text: String) async -> String? {
    guard let url = Self.addresses(in: text).first else { return "Enter a tracker address." }
    return await change { actions, hash in try await actions.editTracker(old, to: url, of: hash) }
  }

  /// Takes trackers away.
  public func removeTrackers(_ urls: Set<String>) async {
    guard !urls.isEmpty else { return }
    changeFailure = await change { actions, hash in
      try await actions.removeTrackers(Array(urls), of: hash)
    }
  }

  /// "Ask Again": asks the trackers for peers now.
  public func askAgain() async {
    changeFailure = await change { actions, hash in try await actions.reannounce([hash]) }
  }

  /// "Download again" for a torrent whose files went missing: Umbra checks
  /// the files and fetches what is gone.
  public func downloadAgain() async {
    changeFailure = await change(refreshing: nil) { actions, hash in
      try await actions.recheck([hash])
    }
  }

  /// Runs one change on the selected torrent; returns Umbra's words if it
  /// failed. Afterwards the Trackers tab is fetched again (or `refreshing`).
  private func change(
    refreshing tab: Tab? = .trackers,
    _ send: (TorrentActions, String) async throws -> Void
  ) async -> String? {
    guard let hash = selectedHash, let actions = actions() else {
      return "Umbra isn't connected."
    }
    var failure: String?
    do {
      try await send(actions, hash)
    } catch {
      // Every call here throws `UmbraError`; the closure just can't say so.
      failure = (error as? UmbraError)?.message ?? error.localizedDescription
    }
    if let tab { await refresh(Watch(hash: hash, tab: tab)) }
    return failure
  }
}
