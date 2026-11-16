import Foundation
import Observation
import UmbraAPI

/// What the main window is showing: the chosen sidebar filter, the search,
/// the sort, the selected torrents and whether the inspector is open, and
/// from those the rows the list shows.
///
/// It lives here (not in the views) so every rule is tested. The filter,
/// sort and inspector are remembered across launches in `defaults`; tests
/// pass a throwaway set of defaults.
@MainActor @Observable
public final class MainWindowModel {
  // MARK: The person's choices

  /// The sidebar's choice. Remembered.
  public var filter: TorrentFilter {
    didSet {
      guard filter != oldValue else { return }
      defaults.set(filter.key, forKey: Keys.filter)
      updateVisibleRows()
    }
  }

  /// The search field's text: rows whose name contains it.
  public var searchText = "" {
    didSet { if searchText != oldValue { updateVisibleRows() } }
  }

  /// The list's order. Remembered.
  public var sort: TorrentSort {
    didSet {
      guard sort != oldValue else { return }
      defaults.set(Self.text(of: sort), forKey: Keys.sort)
      updateVisibleRows()
    }
  }

  /// The selected torrents, by hash. Hashes that leave the list (removed,
  /// or no longer matching the filter or search) are dropped; the rest
  /// stay selected through updates and re-sorts.
  public var selection: Set<String> = []

  /// Whether the inspector beside the list is open. Remembered.
  public var inspectorShown: Bool {
    didSet { defaults.set(inspectorShown, forKey: Keys.inspector) }
  }

  /// Goes up each time something (the Find menu item) asks for the search
  /// field to be focused; the window watches it.
  public private(set) var searchFocusRequests = 0

  /// The last action that failed, for an alert; set back to nil to dismiss it.
  public var actionFailure: ActionFailure?

  /// The torrents whose Limits sheet is open; nil when it is closed.
  public var limitsRequest: LimitsRequest?
  /// Counts saved Limits sheets, so the inspector asks Umbra again.
  public var limitsSaves = 0

  /// Torrents to select as soon as the list shows them (one just added
  /// arrives through the live feed a moment after Umbra says it's added),
  /// and until when to keep waiting. See MainWindowModel+Adding.swift.
  @ObservationIgnored var pendingSelection: (hashes: [String], until: Date)?

  // MARK: What the actions menus need (see MainWindowModel+Actions.swift)

  /// The categories Umbra has set up in Settings, for the Category menu.
  /// (The sidebar's counts only know the ones some torrent uses.)
  public var definedCategories: [String] = []
  /// Goes up each time Umbra says a settings group changed, so the window
  /// can ask for the categories again.
  public internal(set) var settingsChangeCount = 0
  /// Slow mode as the person just set it, until the next totals from the
  /// feed (which carry the real state) replace it: `base` is the totals
  /// it was set against.
  var slowModeSetting: (value: Bool, base: Components.Schemas.Transfer?)?

  // MARK: What the window shows

  /// Every torrent, as list rows, in the feed's order.
  public private(set) var allRows: [TorrentRow] = []
  /// The rows the list shows: filtered, searched and sorted.
  public private(set) var visibleRows: [TorrentRow] = []
  /// The sidebar's numbers (over all torrents, not just the visible ones).
  public private(set) var counts = TorrentCounts([])

  /// The sidebar's sections and rows.
  public var sidebarSections: [SidebarSection] { SidebarSection.all(for: counts) }

  /// The window's title: the current filter's name.
  public var title: String { filter.title }

  /// The window's subtitle: "12 torrents", or "3 of 12 selected".
  public var subtitle: String {
    let shown = visibleRows.count
    if selection.isEmpty { return shown == 1 ? "1 torrent" : "\(Format.count(shown)) torrents" }
    return "\(Format.count(selection.count)) of \(Format.count(shown)) selected"
  }

  /// The selected hashes in the order the list shows them (for actions).
  public var selectedHashes: [String] {
    visibleRows.lazy.map(\.id).filter { self.selection.contains($0) }
  }

  // MARK: Setting up

  let store: TorrentStore
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored let now: () -> Date
  @ObservationIgnored private let dateStyle: Format.DateStyle
  /// The torrents the rows were last made from, to skip work when only the
  /// totals changed.
  @ObservationIgnored private var madeFrom: [Components.Schemas.Torrent]?
  /// Keeps this model on the store's list of settings listeners.
  @ObservationIgnored private var settingsSubscription: SettingsSubscription?

  public init(
    store: TorrentStore, defaults: UserDefaults = .standard,
    now: @escaping () -> Date = { Date() }, dateStyle: Format.DateStyle = .current
  ) {
    self.store = store
    self.defaults = defaults
    self.now = now
    self.dateStyle = dateStyle
    filter = defaults.string(forKey: Keys.filter).map(TorrentFilter.init(key:)) ?? .all
    sort = defaults.string(forKey: Keys.sort).flatMap(Self.sort(from:)) ?? .default
    inspectorShown = defaults.bool(forKey: Keys.inspector)
    refreshRows()
    watchStore()
    // Hear about settings changes (alongside any other listener).
    settingsSubscription = store.listenForSettingsChanges { [weak self] _ in
      self?.settingsChangeCount += 1
    }
  }

  // MARK: Following the store

  /// Remakes the rows whenever the store's list changes. Observation tells
  /// once per change, so this signs up again each time.
  private func watchStore() {
    withObservationTracking {
      _ = store.feed
    } onChange: { [weak self] in
      // Told just before the change; act just after it, on the main actor.
      Task { @MainActor [weak self] in
        self?.refreshRows()
        self?.watchStore()
      }
    }
  }

  /// Makes the rows from the store's torrents now.
  func refreshRows() {
    let torrents = store.torrents
    guard torrents != madeFrom else { return }
    madeFrom = torrents
    let date = now()
    allRows = torrents.map { TorrentRow($0, now: date, style: dateStyle) }
    let newCounts = TorrentCounts(allRows)
    if newCounts != counts { counts = newCounts }
    updateVisibleRows()
    selectPendingIfListed()
  }

  /// Filters, searches and sorts, then drops selected hashes no longer shown.
  private func updateVisibleRows() {
    let query = searchText.trimmingCharacters(in: .whitespaces)
    let rows = sort.sorted(allRows.filter { filter.matches($0, query: query) })
    if rows != visibleRows { visibleRows = rows }
    let shown = Set(rows.map(\.id))
    let kept = selection.intersection(shown)
    if kept != selection { selection = kept }
  }

  // MARK: Commands

  /// Asks the window to put the cursor in the search field (Edit → Find…).
  public func requestSearchFocus() { searchFocusRequests += 1 }

  /// Whether toolbar actions on the selection can run now.
  public func canAct(with actions: TorrentActions?) -> Bool {
    actions != nil && !selection.isEmpty
  }

  /// Runs `action` on the selected torrents; a failure is kept in
  /// `actionFailure` (with Umbra's own explanation) for an alert. The list
  /// itself changes when the live feed reports the result.
  public func perform(_ action: TorrentActions.Action, using actions: TorrentActions?) async {
    let hashes = selectedHashes
    guard let actions, !hashes.isEmpty else { return }
    do {
      try await actions.perform(action, on: hashes)
    } catch {
      actionFailure = ActionFailure(action: action, count: hashes.count, message: error.message)
    }
  }

  // MARK: Remembering

  enum Keys {
    static let filter = "MainWindow.filter"
    static let sort = "MainWindow.sort"
    static let inspector = "MainWindow.inspectorShown"
  }

  /// "addedAt descending": the sort as remembered.
  static func text(of sort: TorrentSort) -> String {
    "\(sort.column.rawValue) \(sort.descending ? "descending" : "ascending")"
  }

  /// Reads a remembered sort; nil if it isn't one (a column since removed, say).
  static func sort(from text: String) -> TorrentSort? {
    let parts = text.split(separator: " ")
    guard parts.count == 2, let column = TorrentColumn(rawValue: String(parts[0])),
      ["ascending", "descending"].contains(parts[1])
    else { return nil }
    return TorrentSort(column: column, descending: parts[1] == "descending")
  }
}

/// An action that didn't work, as an alert shows it.
public struct ActionFailure: Equatable, Sendable {
  /// "Couldn't pause 3 torrents"
  public let title: String
  /// Umbra's own explanation.
  public let message: String

  public init(action: TorrentActions.Action, count: Int, message: String) {
    self.init(verb: action.verb, count: count, message: message)
  }

  /// "Couldn't <verb> the torrent" or "Couldn't <verb> 3 torrents".
  public init(verb: String, count: Int, message: String) {
    let what = count == 1 ? "the torrent" : "\(Format.count(count)) torrents"
    self.init(title: "Couldn't \(verb) \(what)", message: message)
  }

  public init(title: String, message: String) {
    self.title = title
    self.message = message
  }
}

extension TorrentActions.Action {
  /// The action in words, for "Couldn't … the torrent".
  public var verb: String {
    switch self {
    case .pause: "pause"
    case .resume: "resume"
    case .forceStart: "force-start"
    case .recheck: "verify"
    case .reannounce: "reannounce"
    case .queueTop, .queueUp, .queueDown, .queueBottom: "move in the queue"
    }
  }
}
