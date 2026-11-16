import Foundation
import Observation
import UmbraAPI

/// The Add sheet: what is being added, what Umbra says it is, the choices
/// for it, and adding it. It follows the web page's Add dialog
/// (`web/src/components/dialogs/AddDialog.tsx`) step by step.
///
/// The source is either .torrent files (one or several) or one link (a
/// magnet link or the web address of a .torrent file); a new one replaces
/// the old. Each is shown to Umbra first (inspect), which says what it is
/// without adding anything. A magnet link's files aren't known at first:
/// Umbra fetches them while the sheet is open, and the sheet asks every
/// second until they come; Add works straight away all the same. Closing
/// the sheet without adding tells Umbra to stop, so nothing is left behind.
///
/// Umbra decides everything (what a file or link is, duplicates, whether
/// it can be added); this only asks and shows the answers.
@MainActor @Observable
public final class AddTorrentModel {
  public typealias Preview = Components.Schemas.TorrentPreview
  public typealias Existing = Components.Schemas.ExistingTorrent
  /// How to wait (tests pass one that waits only when they say).
  public typealias Sleep = @Sendable (Duration) async throws -> Void

  // MARK: What the sheet shows

  /// The sheet as a whole, for its wording and buttons.
  public enum Phase: Equatable, Sendable {
    /// Nothing chosen or typed yet.
    case empty
    /// Asking Umbra what it is.
    case inspecting
    /// Known, and ready to add.
    case ready
    /// A magnet link, ready to add while its details are fetched.
    case waitingForDetails
    /// Umbra has this torrent already.
    case duplicate
    /// Umbra turned it down; its message is on the item (or `addFailure`).
    case refused
    /// The Add button was pressed and Umbra hasn't answered yet.
    case adding
  }

  /// One .torrent file, or the link.
  public struct Item: Identifiable, Equatable, Sendable {
    public let id: Int
    /// The file's name or the link as typed, until Umbra names it.
    public let label: String
    public let input: TorrentActions.AddInput
    public internal(set) var state: State

    public enum State: Equatable, Sendable {
      case inspecting
      /// Its details are known (always so for a .torrent file).
      case ready(Preview)
      /// A magnet link whose details Umbra is fetching.
      case waiting(Preview)
      case duplicate(Preview, Existing)
      /// Umbra's own words for why not.
      case refused(String)
      /// Added; Umbra's hash for it.
      case added(String)
    }

    public var isLink: Bool {
      if case .torrentFile = input { return false }
      return true
    }

    public var preview: Preview? {
      switch state {
      case .ready(let p), .waiting(let p), .duplicate(let p, _): p
      default: nil
      }
    }

    /// The torrent's name once Umbra has said, otherwise the label.
    public var name: String { preview?.name ?? label }

    /// Ready or waiting: something Add will add.
    public var isNew: Bool {
      switch state {
      case .ready, .waiting: true
      default: false
      }
    }

    /// "18.4 GB · 214 files · 3 trackers · private"
    public var summary: String? {
      guard let p = preview else { return nil }
      var parts: [String] = []
      if let size = p.size, p.detailsKnown { parts.append(Format.bytes(size)) }
      if let files = p.files, p.detailsKnown {
        parts.append(files.count == 1 ? "1 file" : "\(Format.count(files.count)) files")
      }
      parts.append(p.trackers.count == 1 ? "1 tracker" : "\(p.trackers.count) trackers")
      if p._private { parts.append("private") }
      return parts.joined(separator: " · ")
    }
  }

  /// What was chosen or typed, as Umbra has described it so far.
  public private(set) var items: [Item] = []

  /// The link field. Typing in it replaces whatever was there before
  /// (files too) once the typing stops for a moment.
  public var linkText = "" {
    didSet { if linkText != oldValue, !settingLink { linkChanged(debounced: true) } }
  }
  /// Set when the link field holds something that is neither a magnet link
  /// nor a web address.
  public private(set) var linkNote: String?

  // MARK: The choices

  /// "" for none.
  public var category = ""
  public private(set) var tags: [String] = []
  public var startPaused = false

  /// The files of a single torrent, with tick boxes. Nil until its details
  /// are known, and with several torrents (they are added whole, as on
  /// the web page).
  public private(set) var fileTree: FileTree?
  /// Folders shown closed in the tree.
  public private(set) var collapsed: Set<String> = []

  /// The rows the tree shows, closed folders' contents left out.
  public var visibleNodes: [FileTree.Node] { fileTree?.visibleNodes(collapsed: collapsed) ?? [] }

  /// Where it will be saved; nil until Umbra has said.
  public var saveFolder: String? { folders?.folder(for: category) }

  /// None, then each category Umbra has (set up in Settings, or in use).
  public var categories: [String] {
    var seen = Set<String>()
    return ((folders?.categoryNames ?? []) + knownCategories).filter {
      !$0.isEmpty && seen.insert($0).inserted
    }
  }

  /// Tags in use that aren't chosen yet, for the Tags menu.
  public var tagSuggestions: [String] {
    knownTags.filter { !tags.contains($0) }.sorted {
      $0.localizedStandardCompare($1) == .orderedAscending
    }
  }

  // MARK: Adding and its outcome

  public private(set) var isAdding = false
  /// Why the last Add didn't work (Umbra's words); the sheet stays open.
  public private(set) var addFailure: String?
  /// Why adding trackers to the torrent already there didn't work.
  public private(set) var trackerFailure: String?
  /// Set once the sheet's work is done and it should close.
  public private(set) var isFinished = false

  public var phase: Phase {
    if isAdding { return .adding }
    if items.isEmpty { return .empty }
    if addFailure != nil { return .refused }
    if items.contains(where: { $0.state == .inspecting }) { return .inspecting }
    let fresh = newItems
    if fresh.contains(where: { if case .waiting = $0.state { true } else { false } }) {
      return .waitingForDetails
    }
    if !fresh.isEmpty { return .ready }
    if items.contains(where: { if case .duplicate = $0.state { true } else { false } }) {
      return .duplicate
    }
    return .refused
  }

  /// The items Add will add.
  public var newItems: [Item] { items.filter(\.isNew) }

  public var canAdd: Bool { !isAdding && !isFinished && !closed && !newItems.isEmpty }

  /// "Add", "Add Now" (a magnet still fetching its details) or "Add 3 Torrents".
  public var addTitle: String {
    let fresh = newItems
    if fresh.contains(where: { if case .waiting = $0.state { true } else { false } }) {
      return "Add Now"
    }
    return fresh.count > 1 ? "Add \(Format.count(fresh.count)) Torrents" : "Add"
  }

  /// "214 files · 16.1 GB of 18.4 GB selected"
  public var filesSummary: String? {
    guard let totals = fileTree?.totals else { return nil }
    let files = totals.fileCount == 1 ? "1 file" : "\(Format.count(totals.fileCount)) files"
    let size =
      totals.wantedSize == totals.size
      ? Format.bytes(totals.size)
      : "\(Format.bytes(totals.wantedSize)) of \(Format.bytes(totals.size)) selected"
    return "\(files) · \(size)"
  }

  // MARK: Setting up

  @ObservationIgnored private let actions: TorrentActions
  @ObservationIgnored private let knownCategories: [String]
  @ObservationIgnored private let knownTags: [String]
  @ObservationIgnored private let select: @MainActor ([String]) -> Void
  @ObservationIgnored private let sleep: Sleep
  @ObservationIgnored private let typingPause: Duration
  @ObservationIgnored private let pollInterval: Duration
  private var folders: SaveFolders?

  @ObservationIgnored private var nextID = 1
  private var closed = false
  /// The items whose add Umbra hasn't answered yet.
  @ObservationIgnored private var adding: Set<Int> = []
  @ObservationIgnored private var selected = false
  @ObservationIgnored private var settingLink = false
  @ObservationIgnored private var typingTask: Task<Void, Never>?
  @ObservationIgnored private var polls: [Int: Task<Void, Never>] = [:]
  /// The torrents to select in the list once the sheet is done.
  @ObservationIgnored private var toSelect: [String] = []
  /// One per file of the single torrent, in its order: what Add sends.
  @ObservationIgnored private var priorities: [FileTree.Priority] = []
  /// Which item the file tree is for.
  @ObservationIgnored private var treeItem: (id: Int, hash: String)?

  /// - Parameters:
  ///   - actions: Umbra's calls (the sheet opens only while connected).
  ///   - categories, tags: those in use in the list, for the menus.
  ///   - select: selects torrents in the main list (the one just added, or
  ///     the one already there).
  ///   - typingPause: how long typing must stop before a link is looked at.
  public init(
    actions: TorrentActions, categories: [String] = [], tags: [String] = [],
    select: @escaping @MainActor ([String]) -> Void = { _ in },
    typingPause: Duration = .milliseconds(350), pollInterval: Duration = .seconds(1),
    sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
  ) {
    self.actions = actions
    knownCategories = categories
    knownTags = tags
    self.select = select
    self.typingPause = typingPause
    self.pollInterval = pollInterval
    self.sleep = sleep
  }

  /// Asks where torrents are saved, for the "Save to" line. Without an
  /// answer the line is simply left out.
  public func loadFolders() async {
    if let answer = try? await actions.saveFolders() { folders = answer }
  }

  // MARK: Choosing what to add

  /// Uses these .torrent files instead of what was there.
  public func choose(files: [(name: String, data: Data)]) {
    guard !files.isEmpty else { return }
    clearLink()
    replaceItems(
      with: files.map { file in (label: file.name, input: .torrentFile(file.data)) })
  }

  /// Reads the .torrent files chosen in the open panel and uses them. A
  /// file that can't be read shows why in its place.
  public func choose(fileURLs: [URL]) {
    guard !fileURLs.isEmpty else { return }
    clearLink()
    var readable: [(label: String, input: TorrentActions.AddInput)] = []
    var unreadable: [(String, String)] = []
    for url in fileURLs {
      do {
        readable.append((url.lastPathComponent, .torrentFile(try Data(contentsOf: url))))
      } catch {
        unreadable.append(
          (url.lastPathComponent, "Couldn't read the file: \(error.localizedDescription)"))
      }
    }
    replaceItems(with: readable)
    for (name, message) in unreadable {
      items.append(
        Item(id: takeID(), label: name, input: .torrentFile(Data()), state: .refused(message)))
    }
  }

  /// Uses this link (from outside the app, say a magnet link clicked in a
  /// browser) at once, as if it had been typed and the person had stopped
  /// typing. It is only shown to Umbra; nothing is added until Add.
  public func choose(link: String) {
    settingLink = true
    linkText = link
    settingLink = false
    linkChanged(debounced: false)
  }

  private func clearLink() {
    typingTask?.cancel()
    settingLink = true
    linkText = ""
    settingLink = false
    linkNote = nil
  }

  private func linkChanged(debounced: Bool) {
    typingTask?.cancel()
    addFailure = nil
    let text = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
    // The old source goes at once: what it said no longer applies.
    if text.isEmpty {
      linkNote = nil
      if items.contains(where: \.isLink) { replaceItems(with: []) }
      return
    }
    replaceItems(with: [])
    guard let input = AddLink.input(from: text) else {
      linkNote = "That isn't a magnet link or a web address (http:// or https://)."
      return
    }
    linkNote = nil
    guard debounced, typingPause > .zero else {
      replaceItems(with: [(label: text, input: input)])
      return
    }
    typingTask = Task { [weak self, typingPause, sleep] in
      do { try await sleep(typingPause) } catch { return }
      guard let self, !Task.isCancelled, !self.closed else { return }
      self.replaceItems(with: [(label: text, input: input)])
    }
  }

  /// Drops what was there (calling off any magnet's wait) and inspects
  /// the new ones.
  private func replaceItems(with new: [(label: String, input: TorrentActions.AddInput)]) {
    for item in items { forget(item) }
    addFailure = nil
    trackerFailure = nil
    items = new.map { Item(id: takeID(), label: $0.label, input: $0.input, state: .inspecting) }
    refreshTree()
    for item in items { inspect(item) }
  }

  private func takeID() -> Int {
    defer { nextID += 1 }
    return nextID
  }

  // MARK: Asking Umbra

  private func inspect(_ item: Item) {
    Task {
      let state: Item.State
      do throws(UmbraError) {
        state = Self.state(for: try await actions.inspect(item.input))
      } catch {
        state = .refused(Self.words(for: error))
      }
      guard isCurrent(item.id) else {
        // Replaced or closed meanwhile: what came back no longer matters,
        // but a magnet Umbra started waiting on must not be left behind.
        if !adding.contains(item.id) { cancelWait(state.previewIfWaiting) }
        return
      }
      update(item.id, to: state)
    }
  }

  /// What Umbra's description of a torrent means for the sheet.
  private static func state(for preview: Preview) -> Item.State {
    if let existing = preview.existing { return .duplicate(preview, existing) }
    if preview.waiting == true, !preview.detailsKnown { return .waiting(preview) }
    return .ready(preview)
  }

  /// Umbra's words for a refusal: the field it names (as the web page
  /// shows), or its message.
  static func words(for error: UmbraError) -> String {
    error.fields.sorted { $0.key < $1.key }.first?.value ?? error.message
  }

  private func update(_ id: Int, to state: Item.State) {
    guard let at = items.firstIndex(where: { $0.id == id }) else { return }
    items[at].state = state
    refreshTree()
    if case .waiting = state { startPolling(id) } else { stopPolling(id) }
  }

  private func isCurrent(_ id: Int) -> Bool {
    !closed && items.contains { $0.id == id }
  }

  /// Asks every second for a waiting magnet's details until they come.
  private func startPolling(_ id: Int) {
    guard polls[id] == nil else { return }
    polls[id] = Task { [weak self, pollInterval, sleep] in
      while !Task.isCancelled {
        do { try await sleep(pollInterval) } catch { return }
        guard let self, self.isCurrent(id), !Task.isCancelled,
          let item = self.items.first(where: { $0.id == id }),
          case .waiting(let old) = item.state
        else { return }
        let state: Item.State
        do {
          let new = try await self.actions.waitingTorrent(old.hash)
          state = Self.state(for: Self.merge(new, into: old))
        } catch {
          // Forgotten meanwhile (an hour passed, or Umbra restarted).
          state = .refused(
            "Umbra stopped waiting for this magnet link's details. Paste it again.")
        }
        guard !Task.isCancelled, self.isCurrent(id) else { return }
        // Still waiting: this same loop asks again (update leaves it running).
        self.update(id, to: state)
        if case .waiting = state {} else { return }
      }
    }
  }

  private func stopPolling(_ id: Int) {
    polls[id]?.cancel()
    polls[id] = nil
  }

  /// A newer answer about a waiting magnet, keeping what only the first
  /// answer carried (the link to add with, for one a web address gave).
  private static func merge(_ new: Preview, into old: Preview) -> Preview {
    var merged = new
    merged.magnet = new.magnet ?? old.magnet
    merged.torrentFile = new.torrentFile ?? old.torrentFile
    merged.existing = new.existing ?? old.existing
    return merged
  }

  /// Lets go of an item: stops asking about it and, if Umbra is waiting
  /// on it and it wasn't added, tells Umbra to stop.
  private func forget(_ item: Item) {
    stopPolling(item.id)
    // One being added right now is Umbra's to finish: adding a waiting
    // magnet adds it in place.
    guard !adding.contains(item.id) else { return }
    cancelWait(item.state.previewIfWaiting)
  }

  private func cancelWait(_ preview: Preview?) {
    guard let preview else { return }
    // Nobody waits for the answer: a magnet already forgotten is fine.
    Task { [actions] in try? await actions.cancelWaiting(preview.hash) }
  }

  // MARK: Files

  /// Builds the tree when there is one torrent with known files.
  private func refreshTree() {
    let fresh = newItems
    let single =
      fresh.count == 1 && items.filter({ !$0.state.isRefused }).count == 1 ? fresh.first : nil
    guard let item = single, let preview = item.preview, preview.detailsKnown,
      let files = preview.files, !files.isEmpty
    else {
      fileTree = nil
      treeItem = nil
      priorities = []
      return
    }
    if let treeItem, treeItem.id == item.id, treeItem.hash == preview.hash { return }
    treeItem = (item.id, preview.hash)
    priorities = Array(repeating: .normal, count: files.count)
    collapsed = []
    fileTree = FileTree(
      files: files.enumerated().map { index, file in
        FileTree.File(index: index, path: file.path, size: file.size, done: 0, priority: .normal)
      })
  }

  /// A click on a tick box: on turns off; off or mixed turns on.
  public func click(_ node: FileTree.Node) {
    guard let tree = fileTree else { return }
    apply(tree.changesForClick(on: node))
  }

  /// Ticks every file.
  public func selectAll() { setAll(.normal) }

  /// Unticks every file.
  public func selectNone() { setAll(.skip) }

  private func setAll(_ priority: FileTree.Priority) {
    var changes: [Int: FileTree.Priority] = [:]
    for index in priorities.indices where priorities[index] != priority {
      changes[index] = priority
    }
    apply(changes)
  }

  private func apply(_ changes: [Int: FileTree.Priority]) {
    guard let tree = fileTree, !changes.isEmpty else { return }
    for (index, priority) in changes where priorities.indices.contains(index) {
      priorities[index] = priority
    }
    fileTree = tree.applying(changes)
  }

  /// Opens or closes a folder in the tree.
  public func toggleFolder(_ id: String) {
    if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
  }

  // MARK: Tags

  /// Adds a tag (typed, or chosen from those in use). A trailing comma is
  /// dropped, as on the web page; an empty or repeated tag is ignored.
  public func addTag(_ text: String) {
    var tag = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if tag.hasSuffix(",") { tag = String(tag.dropLast()).trimmingCharacters(in: .whitespaces) }
    guard !tag.isEmpty, !tags.contains(tag) else { return }
    tags.append(tag)
  }

  public func removeTag(_ tag: String) { tags.removeAll { $0 == tag } }

  // MARK: Adding

  /// Adds every new item with the sheet's choices. A second press while
  /// Umbra is answering does nothing. When all are added the sheet is
  /// finished and the new torrents are selected; a refusal stays in the
  /// sheet with what was chosen.
  public func add() async {
    guard canAdd else { return }
    isAdding = true
    addFailure = nil
    let fresh = newItems
    let chosen = fileTree != nil && priorities.contains(.skip) ? priorities : nil
    var failed = false
    for item in fresh {
      // A magnet's details may come in meanwhile; the add takes them.
      stopPolling(item.id)
      adding.insert(item.id)
      defer { adding.remove(item.id) }
      do throws(UmbraError) {
        let input = try Self.addInput(for: item)
        let result = try await actions.add(
          input, category: category, tags: tags, paused: startPaused,
          filePriorities: fresh.count == 1 ? chosen : nil)
        // Already there (added by someone else since it was looked at):
        // nothing new was added; that one is selected instead.
        update(item.id, to: .added(result.hash))
        toSelect.append(result.hash)
      } catch {
        failed = true
        if fresh.count == 1 {
          addFailure = Self.words(for: error)
          if case .waiting = item.state { startPolling(item.id) }
        } else {
          update(item.id, to: .refused(Self.words(for: error)))
        }
      }
    }
    isAdding = false
    if !failed {
      finish()
    } else if closed {
      // The sheet went away mid-add: still select what was added.
      selectChosen()
    }
  }

  /// What Add sends for an item: the .torrent file, the file a web address
  /// gave, or the magnet link.
  private static func addInput(for item: Item) throws(UmbraError) -> TorrentActions.AddInput {
    if case .torrentFile(let data) = item.input { return .torrentFile(data) }
    if let file = item.preview?.torrentFile { return .torrentFile(Data(file.data)) }
    if let magnet = item.preview?.magnet { return .magnet(magnet) }
    if case .magnet(let link) = item.input { return .magnet(link) }
    throw .unexpectedAnswer
  }

  // MARK: Already in the list

  /// Gives the torrent already in the list this one's trackers it lacks,
  /// then selects it and finishes.
  public func addTrackersToExisting() async {
    guard !isAdding, !closed, let existing = duplicate?.existing, !existing.newTrackers.isEmpty
    else { return }
    isAdding = true
    trackerFailure = nil
    do throws(UmbraError) {
      try await actions.addTrackers(existing.newTrackers, to: existing.hash)
      isAdding = false
      toSelect.append(existing.hash)
      finish()
    } catch {
      isAdding = false
      trackerFailure = error.message
    }
  }

  /// Closes the sheet and selects the torrent that is already there.
  public func showExisting() {
    guard !closed, let existing = duplicate?.existing else { return }
    toSelect.append(existing.hash)
    finish()
  }

  /// The single duplicate item, for the notice's buttons.
  public var duplicate: (item: Item, existing: Existing)? {
    for item in items {
      if case .duplicate(_, let existing) = item.state { return (item, existing) }
    }
    return nil
  }

  /// "Sample.Set is already in your list (seeding). It has 1 tracker that
  /// the existing torrent doesn't." (the web page's words). The second
  /// sentence goes once there's nothing new to add.
  public var duplicateText: String? {
    guard let existing = duplicate?.existing else { return nil }
    let state = StatusKind(existing.state).label.lowercased()
    var text = "\(existing.name) is already in your list (\(state))."
    let count = existing.newTrackers.count
    if count > 0 {
      let trackers = count == 1 ? "1 tracker" : "\(Format.count(count)) trackers"
      text += " It has \(trackers) that the existing torrent doesn’t."
    }
    return text
  }

  /// "Fetching details… connected to 3 peers. The file list appears here
  /// as soon as it arrives." (the web page's words), for a waiting magnet.
  public static func waitingText(_ item: Item) -> String {
    let peers = item.preview?.peers ?? 0
    return
      "Fetching details… connected to \(Format.count(peers)) \(peers == 1 ? "peer" : "peers"). "
      + "The file list appears here as soon as it arrives."
  }

  // MARK: Pictures of the sheet

  /// Shows these items as if Umbra had described them, without asking it
  /// anything (for `just snapshot`).
  public func showFixture(
    _ fixture: [(label: String, input: TorrentActions.AddInput, state: Item.State)],
    link: String = "", folders: SaveFolders? = nil, addFailure: String? = nil
  ) {
    settingLink = true
    linkText = link
    settingLink = false
    items = fixture.map { Item(id: takeID(), label: $0.label, input: $0.input, state: $0.state) }
    self.folders = folders
    self.addFailure = addFailure
    refreshTree()
  }

  // MARK: Closing

  private func finish() {
    isFinished = true
    close()
  }

  /// The sheet is going away: stops asking Umbra about anything, calls off
  /// every magnet's wait that wasn't added, and selects what was added.
  /// Safe to call more than once.
  public func close() {
    guard !closed else { return }
    closed = true
    typingTask?.cancel()
    for item in items { forget(item) }
    selectChosen()
  }

  /// Selects, once, what the sheet added (or found already there).
  private func selectChosen() {
    guard !selected, !toSelect.isEmpty else { return }
    selected = true
    select(toSelect)
  }
}

extension AddTorrentModel.Item.State {
  var isRefused: Bool {
    if case .refused = self { return true }
    return false
  }

  /// The description of a magnet Umbra is waiting on (and that wasn't added).
  var previewIfWaiting: AddTorrentModel.Preview? {
    switch self {
    case .ready(let p), .waiting(let p), .duplicate(let p, _): p.waiting == true ? p : nil
    default: nil
    }
  }
}
