import Foundation
import Testing
import UmbraAPI

@testable import UmbraKit

/// A set of defaults of its own, emptied first, so tests never touch the app's.
@MainActor
func throwawayDefaults(_ name: String = #function) -> UserDefaults {
  let suite = "UmbraKitTests.\(name)"
  let defaults = UserDefaults(suiteName: suite)!
  defaults.removePersistentDomain(forName: suite)
  return defaults
}

/// Four torrents: two downloading (one in "films"), one seeding, one paused with a tag.
func sampleTorrents() -> [Components.Schemas.Torrent] {
  [
    torrent("a1", name: "Alpha") {
      $0.state = .downloading
      $0.size = 100
      $0.category = "films"
      $0.addedAt = testNow.addingTimeInterval(-40)
    },
    torrent("b2", name: "Bravo") {
      $0.state = .downloading
      $0.size = 400
      $0.addedAt = testNow.addingTimeInterval(-30)
    },
    torrent("c3", name: "Charlie") {
      $0.state = .seeding
      $0.progress = 1
      $0.size = 300
      $0.addedAt = testNow.addingTimeInterval(-20)
    },
    torrent("d4", name: "Delta") {
      $0.state = .paused
      $0.size = 200
      $0.tags = ["keep"]
      $0.addedAt = testNow.addingTimeInterval(-10)
    },
  ]
}

@MainActor
func makeModel(
  _ torrents: [Components.Schemas.Torrent] = sampleTorrents(), defaults: UserDefaults
) -> (MainWindowModel, TorrentStore) {
  var feed = FeedState()
  feed.applySnapshot(.init(rev: 1, torrents: torrents))
  let store = TorrentStore.fixture(feed)
  let model = MainWindowModel(
    store: store, defaults: defaults, now: { testNow }, dateStyle: testStyle)
  return (model, store)
}

/// Lets the model's "the store changed" work run.
@MainActor
func settle() async {
  for _ in 0..<10 { await Task.yield() }
}

@MainActor @Suite struct MainWindowModelTests {
  @Test func showsEverythingNewestFirstAtFirst() {
    let (model, _) = makeModel(defaults: throwawayDefaults())
    #expect(model.filter == .all)
    #expect(model.sort == .default)
    #expect(model.visibleRows.map(\.id) == ["d4", "c3", "b2", "a1"])
    #expect(model.title == "All Torrents")
    #expect(model.subtitle == "4 torrents")
    #expect(model.inspectorShown == false)
  }

  @Test func filtersSearchesAndSorts() {
    let (model, _) = makeModel(defaults: throwawayDefaults())
    model.filter = .status(.downloading)
    #expect(model.visibleRows.map(\.id) == ["b2", "a1"])
    #expect(model.title == "Downloading")
    model.sort = TorrentSort(column: .name, descending: false)
    #expect(model.visibleRows.map(\.id) == ["a1", "b2"])
    model.searchText = "brav"
    #expect(model.visibleRows.map(\.id) == ["b2"])
    model.searchText = ""
    model.filter = .category("films")
    #expect(model.visibleRows.map(\.id) == ["a1"])
    model.filter = .tag("keep")
    #expect(model.visibleRows.map(\.id) == ["d4"])
    #expect(model.title == "keep")
  }

  @Test func countsCoverEveryTorrentWhateverTheFilter() {
    let (model, _) = makeModel(defaults: throwawayDefaults())
    model.filter = .status(.paused)
    #expect(model.counts.status[.all] == 4)
    #expect(model.counts.status[.downloading] == 2)
    #expect(model.counts.categories == ["films": 1])
  }

  @Test func subtitleSaysHowManyAreSelected() {
    let (model, _) = makeModel(defaults: throwawayDefaults())
    model.selection = ["a1", "c3"]
    #expect(model.subtitle == "2 of 4 selected")
    model.filter = .status(.seeding)
    #expect(model.subtitle == "1 of 1 selected")
    model.selection = []
    #expect(model.subtitle == "1 torrent")
  }

  @Test func selectionSurvivesReSortsAndFiltersThatKeepIt() {
    let (model, _) = makeModel(defaults: throwawayDefaults())
    model.selection = ["a1", "b2"]
    model.sort = TorrentSort(column: .size, descending: true)
    #expect(model.selection == ["a1", "b2"])
    #expect(model.selectedHashes == ["b2", "a1"])  // in the list's order
    model.filter = .status(.downloading)
    #expect(model.selection == ["a1", "b2"])
    model.filter = .category("films")
    #expect(model.selection == ["a1"])  // b2 is no longer shown
    model.searchText = "zzz"
    #expect(model.selection.isEmpty)
  }

  @Test func selectionSurvivesUpdatesButLosesRemovedTorrents() async {
    let (model, store) = makeModel(defaults: throwawayDefaults())
    model.selection = ["a1", "c3"]
    var changed = sampleTorrents()[0]
    changed.progress = 0.5
    store.patch([changed])
    await settle()
    #expect(model.allRows.first { $0.id == "a1" }?.progress == 0.5)
    #expect(model.selection == ["a1", "c3"])

    // c3 is removed (a delta from the feed).
    store.receive(.event(delta(from: 1, rev: 2, removed: ["c3"])))
    store.flush()
    await settle()
    #expect(model.allRows.count == 3)
    #expect(model.selection == ["a1"])
  }

  @Test func followsTheStoreAsItChanges() async {
    let (model, store) = makeModel(defaults: throwawayDefaults())
    let extra = torrent("e5", name: "Echo") {
      $0.state = .queued
      $0.addedAt = testNow
    }
    store.patch([extra])
    await settle()
    #expect(model.visibleRows.first?.id == "e5")
    #expect(model.counts.status[.queued] == 1)
    var renamed = sampleTorrents()[1]
    renamed.name = "Bravo Two"
    store.patch([renamed])
    await settle()
    #expect(model.visibleRows.first { $0.id == "b2" }?.name == "Bravo Two")
  }

  @Test func remembersFilterSortAndInspector() {
    let defaults = throwawayDefaults()
    let (first, _) = makeModel(defaults: defaults)
    first.filter = .tag("keep")
    first.sort = TorrentSort(column: .ratio, descending: false)
    first.inspectorShown = true
    first.searchText = "not remembered"
    first.selection = ["d4"]

    let (second, _) = makeModel(defaults: defaults)
    #expect(second.filter == .tag("keep"))
    #expect(second.sort == TorrentSort(column: .ratio, descending: false))
    #expect(second.inspectorShown)
    #expect(second.searchText.isEmpty)
    #expect(second.selection.isEmpty)
  }

  @Test func aRememberedSortThatMakesNoSenseIsTheDefault() {
    let defaults = throwawayDefaults()
    defaults.set("nonsense", forKey: MainWindowModel.Keys.sort)
    defaults.set("tag:keep", forKey: MainWindowModel.Keys.filter)
    let (model, _) = makeModel(defaults: defaults)
    #expect(model.sort == .default)
    #expect(model.filter == .tag("keep"))
    #expect(
      MainWindowModel.sort(from: "eta ascending") == TorrentSort(column: .eta, descending: false))
    #expect(MainWindowModel.sort(from: "eta sideways") == nil)
  }

  @Test func searchFocusRequestsCount() {
    let (model, _) = makeModel(defaults: throwawayDefaults())
    model.requestSearchFocus()
    model.requestSearchFocus()
    #expect(model.searchFocusRequests == 2)
  }
}

@MainActor @Suite struct MainWindowActionTests {
  let connection = Connection(
    baseURL: URL(string: "http://127.0.0.1:7980")!, credential: .apiKey("key"))

  @Test func pausesTheSelectionInListOrder() async throws {
    let (model, _) = makeModel(defaults: throwawayDefaults())
    let transport = RecordingTransport()
    let actions = TorrentActions(connection: connection, transport: transport)
    #expect(!model.canAct(with: actions))
    model.selection = ["a1", "d4"]
    #expect(model.canAct(with: actions))
    #expect(!model.canAct(with: nil))
    await model.perform(.pause, using: actions)
    let sent = try #require(await transport.sent.first)
    #expect(sent.json == ["action": "pause", "hashes": ["d4", "a1"]])
    #expect(model.actionFailure == nil)
  }

  @Test func aFailureKeepsUmbrasMessageForAnAlert() async {
    let (model, _) = makeModel(defaults: throwawayDefaults())
    let transport = RecordingTransport([
      "torrentAction": .error(.conflict, code: "vpn_down", message: "The VPN is down.")
    ])
    let actions = TorrentActions(connection: connection, transport: transport)
    model.selection = ["b2"]
    await model.perform(.resume, using: actions)
    #expect(
      model.actionFailure
        == ActionFailure(action: .resume, count: 1, message: "The VPN is down."))
    #expect(model.actionFailure?.title == "Couldn't resume the torrent")
  }

  @Test func nothingSelectedSendsNothing() async {
    let (model, _) = makeModel(defaults: throwawayDefaults())
    let transport = RecordingTransport()
    await model.perform(.pause, using: TorrentActions(connection: connection, transport: transport))
    #expect(await transport.sent.isEmpty)
  }
}
