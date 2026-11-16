import Foundation
import Testing
import UmbraAPI

@testable import UmbraKit

// MARK: Helpers

private func rows(_ states: [(String, StatusKind)]) -> [TorrentRow] {
  states.map { hash, kind in
    listRow(
      torrent(hash, name: hash.uppercased()) {
        switch kind {
        case .paused: $0.state = .paused
        case .error: $0.state = .error
        case .missingFiles: $0.state = .missingFiles
        case .fetchingDetails: $0.state = .fetchingDetails
        case .seeding: $0.state = .seeding
        default: $0.state = .downloading
        }
      })
  }
}

private func menu(
  _ selected: [TorrentRow], categories: [String] = [], tags: [String] = [],
  connected: Bool = true, slowMode: Bool = false
) -> TorrentMenu {
  TorrentMenu(
    TorrentMenuContext(
      selection: TorrentSelection(selected), categories: categories, tags: tags,
      connected: connected, slowMode: slowMode))
}

extension TorrentMenuEntry {
  /// Every item in the entry, submenus included.
  var allItems: [TorrentMenuItem] {
    switch self {
    case .item(let item): [item]
    case .submenu(_, _, _, let entries): entries.flatMap(\.allItems)
    case .separator: []
    }
  }
}

extension TorrentMenu {
  var allItems: [TorrentMenuItem] { menuBarEntries.flatMap(\.allItems) }

  func item(_ title: String) -> TorrentMenuItem? { allItems.first { $0.title == title } }

  /// The entries inside the submenu with this title.
  func submenu(_ title: String) -> [TorrentMenuEntry] {
    for case .submenu(let name, _, _, let entries) in entries where name == title {
      return entries
    }
    return []
  }

  func submenuEnabled(_ title: String) -> Bool? {
    for case .submenu(let name, _, let enabled, _) in entries where name == title {
      return enabled
    }
    return nil
  }
}

// MARK: Tests

@Suite("the torrent menu") struct TorrentMenuTests {
  let running = rows([("a1", .downloading)])
  let paused = rows([("b2", .paused)])

  @Test func listsTheItemsInOrder() {
    let m = menu(running)
    let shape: [String] = m.entries.map {
      switch $0 {
      case .item(let item): item.title
      case .submenu(let title, _, _, _): "\(title) ▸"
      case .separator: "-"
      }
    }
    #expect(
      shape == [
        "Pause", "Resume", "Resume Now, Skip Queue", "-",
        "Show in Finder", "Copy Magnet Link", "Copy Info Hash", "Move Data To…", "-",
        "Category ▸", "Tags ▸", "Limits…", "-",
        "Queue ▸", "Verify Local Data", "Ask Trackers for More Peers", "Export .torrent File…",
        "-", "Remove…",
      ])
  }

  @Test func theQueueSubmenuHasFourMoves() {
    let titles = menu(running).submenu("Queue").flatMap(\.allItems)
    #expect(
      titles.map(\.command) == [
        .run(.queueTop), .run(.queueUp), .run(.queueDown), .run(.queueBottom),
      ])
    #expect(titles.map(\.title) == ["Move to Top", "Move Up", "Move Down", "Move to Bottom"])
  }

  @Test func theMenuBarAddsSlowModeAndTheContextMenuDoesNot() {
    let m = menu(running)
    #expect(!m.entries.flatMap(\.allItems).contains { $0.title == "Slow Mode" })
    #expect(m.menuBarEntries.suffix(2).map { $0 } == [.separator, m.slowMode])
  }

  @Test func theOtherMenuBarItemsAreTheContextMenusOwn() {
    #expect(Array(menu(running).menuBarEntries.dropLast(2)) == menu(running).entries)
  }

  // MARK: Enabling

  @Test func pauseNeedsSomethingThatCanBePaused() {
    #expect(menu(running).item("Pause")?.enabled == true)
    #expect(menu(paused).item("Pause")?.enabled == false)
    // One running among paused ones is enough.
    #expect(menu(running + paused).item("Pause")?.enabled == true)
  }

  @Test func resumeNeedsSomethingStopped() {
    #expect(menu(running).item("Resume")?.enabled == false)
    #expect(menu(paused).item("Resume")?.enabled == true)
    #expect(menu(running + paused).item("Resume")?.enabled == true)
    #expect(menu(rows([("e1", .error)])).item("Resume")?.enabled == true)
    #expect(menu(rows([("m1", .missingFiles)])).item("Resume")?.enabled == true)
  }

  @Test func theOtherItemsNeedOnlyASelection() {
    let m = menu(paused)
    for title in [
      "Resume Now, Skip Queue", "Show in Finder", "Copy Magnet Link", "Copy Info Hash",
      "Verify Local Data", "Ask Trackers for More Peers", "Export .torrent File…", "Remove…",
      "Move to Top", "Move Up", "Move Down", "Move to Bottom", "None", "New Tag…",
    ] {
      #expect(m.item(title)?.enabled == true, "\(title)")
    }
    #expect(m.submenuEnabled("Category") == true)
    #expect(m.submenuEnabled("Tags") == true)
    #expect(m.submenuEnabled("Queue") == true)
  }

  @Test func aMagnetStillFetchingHasNoTorrentFileToExport() {
    let fetching = rows([("f1", .fetchingDetails)])
    #expect(menu(fetching).item("Export .torrent File…")?.enabled == false)
    #expect(menu(fetching + running).item("Export .torrent File…")?.enabled == false)
    #expect(menu(fetching).item("Remove…")?.enabled == true)
  }

  @Test func nothingSelectedDimsEverythingButSlowMode() {
    let m = menu([])
    #expect(m.allItems.filter { $0.title != "Slow Mode" }.allSatisfy { !$0.enabled })
    #expect(m.submenuEnabled("Category") == false)
    #expect(m.submenuEnabled("Tags") == false)
    #expect(m.submenuEnabled("Queue") == false)
    #expect(m.item("Slow Mode")?.enabled == true)
  }

  @Test func notConnectedDimsEverything() {
    let m = menu(running + paused, categories: ["films"], tags: ["keep"], connected: false)
    #expect(m.allItems.allSatisfy { !$0.enabled })
    #expect(m.submenuEnabled("Category") == false)
    #expect(m.submenuEnabled("Tags") == false)
  }

  @Test func titlesDontChangeWithTheCount() {
    let one = menu(running).entries
    let many = menu(running + paused + rows([("c3", .seeding)])).entries
    func titles(_ entries: [TorrentMenuEntry]) -> [String] {
      entries.flatMap(\.allItems).map(\.title)
    }
    #expect(titles(one) == titles(many))
  }

  // MARK: Shortcuts

  @Test func shortcutsFollowTheDesign() {
    let m = menu(running)
    #expect(m.item("Pause")?.shortcut?.display == "⌘.")
    #expect(m.item("Resume")?.shortcut?.display == "⌘/")
    #expect(m.item("Show in Finder")?.shortcut?.display == "⌘R")
    #expect(m.item("Copy Magnet Link")?.shortcut?.display == "⇧⌘C")
    #expect(m.item("Remove…")?.shortcut?.display == "⌘⌫")
    #expect(m.item("Slow Mode")?.shortcut?.display == "⇧⌘T")
  }

  @Test func noShortcutRepeatsOrTakesTheOnesAlreadyInUse() {
    let shortcuts = menu(running).allItems.compactMap(\.shortcut)
    #expect(Set(shortcuts.map(\.display)).count == shortcuts.count)
    // Find (⌘F) and the inspector (⌥⌘I) are the window's own.
    #expect(!shortcuts.contains(MenuShortcut("f")))
    #expect(!shortcuts.contains(MenuShortcut("i", option: true)))
  }

  // MARK: Category

  @Test func categoryListsNoneThenEachOneAlphabetically() {
    let m = menu(running, categories: ["movies", "Books", "films", "films"])
    let items = m.submenu("Category")
    #expect(items.flatMap(\.allItems).map(\.title) == ["None", "Books", "films", "movies"])
    #expect(items[1] == .separator)
  }

  @Test func categoryTicksTheCurrentOne() {
    let films = listRow(torrent("a1") { $0.category = "films" })
    let m = menu([films], categories: ["films", "books"])
    #expect(m.submenu("Category").flatMap(\.allItems).map(\.mark) == [.off, .off, .on])
  }

  @Test func categoryTicksNoneWhenNoTorrentHasOne() {
    let m = menu(running, categories: ["films"])
    #expect(m.item("None")?.mark == .on)
    #expect(m.item("films")?.mark == .off)
  }

  @Test func categoryShowsMixedWhenTheSelectionDiffers() {
    let a = listRow(torrent("a1") { $0.category = "films" })
    let b = listRow(torrent("b2") { $0.category = "books" })
    let c = listRow(torrent("c3"))
    let m = menu([a, b, c], categories: ["films", "books"])
    #expect(m.item("films")?.mark == .mixed)
    #expect(m.item("books")?.mark == .mixed)
    #expect(m.item("None")?.mark == .mixed)
  }

  @Test func categoryChoicesNameTheCategoryToSet() {
    let m = menu(running, categories: ["films"])
    #expect(m.item("None")?.command == .setCategory(""))
    #expect(m.item("films")?.command == .setCategory("films"))
  }

  @Test func noCategoriesLeavesJustNone() {
    #expect(menu(running).submenu("Category").flatMap(\.allItems).map(\.title) == ["None"])
  }

  // MARK: Tags

  @Test func tagsListNewTagLast() {
    let m = menu(running, tags: ["keep", "archive"])
    let items = m.submenu("Tags")
    #expect(items.flatMap(\.allItems).map(\.title) == ["archive", "keep", "New Tag…"])
    #expect(items[2] == .separator)
    #expect(m.item("New Tag…")?.command == .newTag)
  }

  @Test func withNoTagsInUseOnlyNewTagShows() {
    #expect(menu(running).submenu("Tags").flatMap(\.allItems).map(\.title) == ["New Tag…"])
  }

  @Test func aTagEveryTorrentHasIsTickedAndTakesItAway() {
    let a = listRow(torrent("a1") { $0.tags = ["keep"] })
    let b = listRow(torrent("b2") { $0.tags = ["keep", "x"] })
    let m = menu([a, b], tags: ["keep", "x"])
    #expect(m.item("keep")?.mark == .on)
    #expect(m.item("keep")?.command == .changeTag("keep", add: false))
  }

  @Test func aTagOnSomeIsMixedAndAddsToTheRest() {
    let a = listRow(torrent("a1") { $0.tags = ["keep"] })
    let b = listRow(torrent("b2"))
    let m = menu([a, b], tags: ["keep"])
    #expect(m.item("keep")?.mark == .mixed)
    #expect(m.item("keep")?.command == .changeTag("keep", add: true))
  }

  @Test func aTagOnNoneIsUntickedAndAdds() {
    let m = menu(running, tags: ["keep"])
    #expect(m.item("keep")?.mark == .off)
    #expect(m.item("keep")?.command == .changeTag("keep", add: true))
  }

  // MARK: Slow mode

  @Test func slowModeIsTickedWhenOnAndChoosingItAsksForTheOpposite() {
    let off = menu(running, slowMode: false).item("Slow Mode")
    #expect(off?.mark == .off)
    #expect(off?.command == .setSlowMode(true))
    let on = menu(running, slowMode: true).item("Slow Mode")
    #expect(on?.mark == .on)
    #expect(on?.command == .setSlowMode(false))
  }

  @Test func slowModeIsDimmedOnlyWithoutUmbra() {
    #expect(menu([], connected: false).item("Slow Mode")?.enabled == false)
    #expect(menu([], connected: true).item("Slow Mode")?.enabled == true)
  }

  // MARK: Selection facts

  @Test func spaceBarPausesWhatRunsOtherwiseResumes() {
    #expect(TorrentSelection(running).spaceAction == .pause)
    #expect(TorrentSelection(paused).spaceAction == .resume)
    #expect(TorrentSelection(running + paused).spaceAction == .pause)
    #expect(TorrentSelection([]).spaceAction == nil)
  }
}
