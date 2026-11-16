import Foundation

/// What choosing a menu item does. The window carries these out; the menu
/// description only names them.
public enum TorrentMenuCommand: Hashable, Sendable {
  /// One of the plain actions Umbra runs on the torrents.
  case run(TorrentActions.Action)
  /// Move the torrents to this category ("" takes the category away).
  case setCategory(String)
  /// Give the torrents this tag, or take it away.
  case changeTag(String, add: Bool)
  /// Ask for a new tag's name, then give it to the torrents.
  case newTag
  case copyMagnetLinks
  case copyInfoHashes
  case exportTorrents
  case showInFinder
  /// Choose a folder, then move the torrents' files there.
  case moveData
  /// Open the Limits sheet: the torrents' own speed limits and seed goals.
  case editLimits
  /// Open the Remove alert.
  case remove
  /// Slow mode on or off (the alternative speed limits).
  case setSlowMode(Bool)
}

/// A tick beside a menu item.
public enum MenuMark: Equatable, Sendable {
  case off, on
  /// Some of the selected torrents have it and some don't.
  case mixed
}

/// One choosable line of a menu.
public struct TorrentMenuItem: Equatable, Sendable {
  public var title: String
  public var command: TorrentMenuCommand
  public var shortcut: MenuShortcut?
  public var enabled: Bool
  /// Nil for an ordinary item; otherwise the item can carry a tick.
  public var mark: MenuMark?
  /// An SF Symbol, for items at the top of the menu.
  public var symbol: String?
}

/// A line of a menu: an item, a submenu or a separator.
public indirect enum TorrentMenuEntry: Equatable, Sendable {
  case item(TorrentMenuItem)
  case submenu(title: String, symbol: String?, enabled: Bool, entries: [TorrentMenuEntry])
  case separator
}

/// What the menu knows about the world when it is drawn.
public struct TorrentMenuContext: Equatable, Sendable {
  /// The selected torrents, in list order.
  public var selection: TorrentSelection
  /// Categories to offer: the ones Umbra has set up, plus any in use.
  public var categories: [String]
  /// Tags to offer: the ones in use (a new tag needs no setting up).
  public var tags: [String]
  /// False while Umbra isn't running: every item is then dimmed.
  public var connected: Bool
  /// Whether slow mode is on.
  public var slowMode: Bool

  public init(
    selection: TorrentSelection, categories: [String] = [], tags: [String] = [],
    connected: Bool, slowMode: Bool = false
  ) {
    self.selection = selection
    self.categories = categories
    self.tags = tags
    self.connected = connected
    self.slowMode = slowMode
  }
}

/// The torrent menu, described once as plain values. The right-click menu
/// (an AppKit menu) and the menu bar's Torrent menu (SwiftUI) are both
/// drawn from this, so they can't disagree. The menu bar's version is the
/// same list followed by Slow Mode, which isn't about one torrent.
public struct TorrentMenu: Equatable, Sendable {
  /// The menu bar's title.
  public static let title = "Torrent"

  /// The right-click menu's entries.
  public let entries: [TorrentMenuEntry]
  /// Slow Mode: a switch on the whole of Umbra, shown in the menu bar only.
  public let slowMode: TorrentMenuEntry

  /// The Torrent menu in the menu bar.
  public var menuBarEntries: [TorrentMenuEntry] { entries + [.separator, slowMode] }

  public init(_ context: TorrentMenuContext) {
    let selection = context.selection
    // Everything is dimmed with nothing selected or without Umbra.
    let live = context.connected && !selection.isEmpty

    func item(
      _ title: String, _ command: TorrentMenuCommand, symbol: String? = nil,
      shortcut: MenuShortcut? = nil, enabled: Bool = live, mark: MenuMark? = nil
    ) -> TorrentMenuEntry {
      .item(
        TorrentMenuItem(
          title: title, command: command, shortcut: shortcut, enabled: enabled, mark: mark,
          symbol: symbol))
    }

    // Categories and tags in the sidebar's order: alphabetical, no repeats.
    func sorted(_ names: [String]) -> [String] {
      Set(names).filter { !$0.isEmpty }.sorted { $0.localizedCompare($1) == .orderedAscending }
    }

    // Category: None, then each one; the ticks show where the selection is now.
    var categoryEntries = [
      item("None", .setCategory(""), mark: selection.mark(category: ""))
    ]
    let categories = sorted(context.categories)
    if !categories.isEmpty {
      categoryEntries.append(.separator)
      categoryEntries += categories.map {
        item($0, .setCategory($0), mark: selection.mark(category: $0))
      }
    }

    // Tags: choosing one gives it to every selected torrent, or, when they
    // all have it already, takes it away.
    var tagEntries: [TorrentMenuEntry] = []
    for tag in sorted(context.tags) {
      let mark = selection.mark(tag: tag)
      tagEntries.append(item(tag, .changeTag(tag, add: mark != .on), mark: mark))
    }
    if !tagEntries.isEmpty { tagEntries.append(.separator) }
    tagEntries.append(item("New Tag…", .newTag))

    entries = [
      item(
        "Pause", .run(.pause), symbol: "pause", shortcut: MenuShortcut("."),
        enabled: live && selection.canPause),
      item(
        "Resume", .run(.resume), symbol: "play", shortcut: MenuShortcut("/"),
        enabled: live && selection.canResume),
      item("Resume Now, Skip Queue", .run(.forceStart), symbol: "forward"),
      .separator,
      item(
        "Show in Finder", .showInFinder, symbol: "magnifyingglass", shortcut: MenuShortcut("r")),
      item(
        "Copy Magnet Link", .copyMagnetLinks, symbol: "link",
        shortcut: MenuShortcut("c", shift: true)),
      item("Copy Info Hash", .copyInfoHashes, symbol: "number"),
      item("Move Data To…", .moveData, symbol: "folder.badge.gearshape"),
      .separator,
      .submenu(title: "Category", symbol: "folder", enabled: live, entries: categoryEntries),
      .submenu(title: "Tags", symbol: "tag", enabled: live, entries: tagEntries),
      item("Limits…", .editLimits, symbol: "gauge.with.dots.needle.50percent"),
      .separator,
      .submenu(
        title: "Queue", symbol: "list.number", enabled: live,
        entries: [
          item("Move to Top", .run(.queueTop)),
          item("Move Up", .run(.queueUp)),
          item("Move Down", .run(.queueDown)),
          item("Move to Bottom", .run(.queueBottom)),
        ]),
      item("Verify Local Data", .run(.recheck), symbol: "arrow.clockwise"),
      item(
        "Ask Trackers for More Peers", .run(.reannounce),
        symbol: "antenna.radiowaves.left.and.right"),
      item(
        "Export .torrent File…", .exportTorrents, symbol: "square.and.arrow.up",
        enabled: live && selection.canExport),
      .separator,
      item("Remove…", .remove, symbol: "trash", shortcut: MenuShortcut(.delete)),
    ]

    // Slow mode works without a selection, but not without Umbra. Choosing
    // it asks for the opposite of what is on now.
    slowMode = .item(
      TorrentMenuItem(
        title: "Slow Mode", command: .setSlowMode(!context.slowMode),
        shortcut: MenuShortcut("t", shift: true), enabled: context.connected,
        mark: context.slowMode ? .on : .off, symbol: nil))
  }
}
