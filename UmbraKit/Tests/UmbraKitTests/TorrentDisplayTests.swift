import AppKit
import Foundation
import Testing
import UmbraAPI

@testable import UmbraKit

/// A fixed "now" and language, so rows read the same on any machine.
let testNow = Date(timeIntervalSince1970: 1_793_000_000)
let testStyle = Format.DateStyle(
  locale: Locale(identifier: "en_GB"), timeZone: TimeZone(identifier: "UTC")!)

/// A list row made from a torrent, as the window makes it.
func listRow(_ t: Components.Schemas.Torrent) -> TorrentRow {
  TorrentRow(t, now: testNow, style: testStyle)
}

/// A torrent with only the parts a test cares about changed.
func torrent(
  _ hash: String = String(repeating: "a", count: 40), name: String = "Made.Up.Film",
  _ change: (inout Components.Schemas.Torrent) -> Void = { _ in }
) -> Components.Schemas.Torrent {
  var t = row(hash, name)
  t.addedAt = testNow
  change(&t)
  return t
}

private let gib: Int64 = 1 << 30
private let wait = Components.Schemas.SpaceWait(
  need: Int64(12.3 * Double(gib)), free: 8 * gib, keep: 5 * gib, others: 0)
private let waiting = torrent {
  $0.state = .waitingForSpace
  $0.progress = 0.2
  $0.spaceWait = wait
}

/// The cases of Umbra's `web/src/lib/torrents.test.ts`, one test per case.
@Suite("a download waiting for disk space")
struct WaitingForSpaceTests {
  @Test("says what it needs in a line") func saysWhatItNeeds() {
    #expect(TorrentRow.spaceLine(waiting) == "Needs 12.3 GB; 8.0 GB free, 5.0 GB kept free")
    var others = waiting
    others.spaceWait?.others = 2 * gib
    #expect(
      TorrentRow.spaceLine(others)
        == "Needs 12.3 GB; 8.0 GB free, 5.0 GB kept free and 2.0 GB for other downloads")
    var queued = waiting
    queued.state = .queued
    #expect(TorrentRow.spaceLine(queued) == nil)
  }

  @Test("counts as queued") func countsAsQueued() {
    #expect(listRow(waiting).group == .queued)
    #expect(TorrentFilter.counts(for: [listRow(waiting)]).status[.queued] == 1)
  }
}

@Suite("a torrent whose files have gone")
struct FilesGoneTests {
  let gone = torrent {
    $0.state = .missingFiles
    $0.progress = 1
    $0.error =
      "The files aren't in /downloads any more: they were moved or deleted outside Umbra."
  }

  @Test("says so in amber, not as a red error") func saysSoInAmber() {
    #expect(TorrentRow.note(gone) == .init(text: gone.error!, role: .orange))
    var failed = gone
    failed.state = .error
    failed.error = "Disk full"
    #expect(TorrentRow.note(failed) == .init(text: "Disk full", role: .red))
  }

  @Test("counts under Errors, where someone would look for it") func countsUnderErrors() {
    #expect(listRow(gone).group == .errors)
  }
}

@Suite("the Peers tab's number")
struct PeersNumberTests {
  @Test("counts the seeds too") func countsTheSeedsToo() {
    // Found in Umbra's local test: a download connected to 17 seeds and no
    // one else showed "Peers 0" over a list of 17.
    #expect(
      listRow(
        torrent {
          $0.seeds = 17
          $0.peers = 0
        }
      ).connected == 17)
    #expect(
      listRow(
        torrent {
          $0.seeds = 3
          $0.peers = 2
        }
      ).connected == 5)
  }
}

@Suite("the swarm's total beside the connected count")
struct SwarmTotalTests {
  @Test("shows when the trackers counted at least as many") func showsWhenAtLeastAsMany() {
    #expect(TorrentRow.swarmTotal(connected: 7, total: 12) == 12)
    #expect(TorrentRow.swarmTotal(connected: 7, total: 7) == 7)
    #expect(TorrentRow.swarmTotal(connected: 0, total: 0) == 0)
  }

  @Test("is left out when it's lower") func leftOutWhenLower() {
    // Seeding to 7 peers found through the DHT read "7 of 0", as the
    // tracker gave no counts.
    #expect(TorrentRow.swarmTotal(connected: 7, total: 0) == nil)
    #expect(TorrentRow.swarmTotal(connected: 7, total: 3) == nil)
  }
}

// MARK: Beyond the web page's tests: the rules in torrents.ts and columns.tsx

@Suite struct StatusKindTests {
  @Test func everyStateHasItsWords() {
    let labels = StatusKind.allCases.map(\.label)
    #expect(
      labels == [
        "Downloading", "Seeding", "Paused", "Queued", "Verifying", "Moving", "Getting metadata",
        "Error", "Waiting for VPN", "Waiting for disk space", "Files missing",
      ])
    for state in Components.Schemas.TorrentState.allCases {
      #expect(StatusKind(state).rawValue == state.rawValue)
    }
  }

  @Test func everySymbolExists() {
    for kind in StatusKind.allCases {
      #expect(
        NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: nil) != nil,
        "\(kind.symbolName) isn't an SF Symbol")
    }
  }

  @Test func coloursFollowTheWebPagesTones() {
    #expect(StatusKind.downloading.textRole == .accent)
    #expect(StatusKind.seeding.textRole == .green)
    #expect(StatusKind.error.textRole == .red)
    #expect(StatusKind.waitingForVpn.textRole == .orange)
    #expect(StatusKind.paused.textRole == .secondary)
    #expect(StatusKind.checking.barRole == .orange)
    #expect(StatusKind.waitingForVpn.barRole == .secondary)
  }

  @Test func unfinishedInBetweenStatesCountAsDownloadingAndFinishedAsSeeding() {
    for kind in [StatusKind.checking, .moving, .waitingForVpn] {
      #expect(StatusFilter.of(kind, progress: 0.5) == .downloading)
      #expect(StatusFilter.of(kind, progress: 1) == .seeding)
    }
    #expect(StatusFilter.of(.fetchingDetails, progress: 0) == .downloading)
    #expect(StatusFilter.of(.error, progress: 1) == .errors)
    #expect(StatusFilter.of(.paused, progress: 1) == .paused)
  }
}

@Suite struct TorrentRowTests {
  @Test func showsTheColumnsAsTheWebPageDoes() {
    let r = listRow(
      torrent {
        $0.size = 31 * gib
        $0.progress = 0.341
        $0.downSpeed = Int64(8.4 * 1024 * 1024)
        $0.upSpeed = 0
        $0.etaSeconds = 41 * 60
        $0.ratio = 2.414
        $0.seeds = 7
        $0.seedsTotal = 12
        $0.peers = 7
        $0.peersTotal = 0
        $0.queuePosition = 3
        $0.tracker = "tracker.example.org"
      })
    #expect(r.sizeText == "31.0 GB")
    #expect(r.progressText == "34%")
    #expect(r.downSpeedText == "8.4 MB/s")
    #expect(r.upSpeedText == Format.dash)
    #expect(r.etaText == "41m")
    #expect(r.ratioText == "2.41")
    #expect(r.seedsText == "7 (12)")
    #expect(r.peersText == "7")
    #expect(r.queueText == "3")
    #expect(r.trackerText == "tracker.example.org")
    #expect(r.categoryText == Format.dash)
    #expect(r.addedText.hasPrefix("Today"))
    #expect(r.completedText == Format.dash)
    #expect(r.statusLabel == "Downloading")
  }

  @Test func aMagnetFetchingDetailsShowsNoSizeOrProgress() {
    let r = listRow(
      torrent {
        $0.state = .fetchingDetails
        $0.progress = 0.5
      })
    #expect(r.sizeText == Format.dash)
    #expect(r.progressText == Format.dash)
    #expect(r.barValue == 0)
  }

  @Test func aTorrentHeldForTheVPNOrDiskShowsNoSpeeds() {
    for state in [Components.Schemas.TorrentState.waitingForVpn, .waitingForSpace] {
      let r = listRow(
        torrent {
          $0.state = state
          $0.downSpeed = 5000
          $0.upSpeed = 5000
        })
      #expect(r.downSpeedText == Format.dash)
      #expect(r.upSpeedText == Format.dash)
    }
  }

  @Test func anErrorWithoutWordsHasNoNote() {
    #expect(listRow(torrent { $0.state = .error }).note == nil)
    #expect(
      listRow(
        torrent {
          $0.state = .paused
          $0.error = "Stopped at its seed ratio of 2"
        }
      ).note == nil)
  }
}

@Suite struct TorrentFilterTests {
  let rows = [
    listRow(
      torrent("1", name: "Ubuntu 24.04") {
        $0.category = "linux"
        $0.tags = ["iso"]
      }),
    listRow(
      torrent("2", name: "Metropolis") {
        $0.state = .seeding
        $0.progress = 1
        $0.category = "films"
        $0.tracker = "bt1.archive.org"
      }),
    listRow(
      torrent("3", name: "Debian") {
        $0.state = .paused
        $0.tags = ["iso", "keep"]
      }),
    listRow(torrent("4", name: "Broken") { $0.state = .error }),
  ]

  @Test func matchesStatusCategoryTagAndTracker() {
    #expect(rows.filter { TorrentFilter.all.matches($0) }.count == 4)
    #expect(rows.filter { TorrentFilter.status(.seeding).matches($0) }.map(\.id) == ["2"])
    #expect(rows.filter { TorrentFilter.status(.errors).matches($0) }.map(\.id) == ["4"])
    #expect(rows.filter { TorrentFilter.category("linux").matches($0) }.map(\.id) == ["1"])
    #expect(rows.filter { TorrentFilter.category("").matches($0) }.map(\.id) == ["3", "4"])
    #expect(rows.filter { TorrentFilter.tag("iso").matches($0) }.map(\.id) == ["1", "3"])
    #expect(rows.filter { TorrentFilter.tracker("bt1.archive.org").matches($0) }.map(\.id) == ["2"])
    #expect(rows.filter { TorrentFilter.tracker("").matches($0) }.map(\.id) == ["1", "3", "4"])
  }

  @Test func searchLooksAnywhereInTheNameIgnoringCapitals() {
    #expect(rows.filter { TorrentFilter.all.matches($0, query: "BUN") }.map(\.id) == ["1"])
    #expect(rows.filter { TorrentFilter.all.matches($0, query: "o") }.map(\.id) == ["2", "4"])
    #expect(rows.filter { TorrentFilter.tag("iso").matches($0, query: "deb") }.map(\.id) == ["3"])
    #expect(rows.filter { TorrentFilter.all.matches($0, query: "zzz") }.isEmpty)
  }

  @Test func countsEveryGroup() {
    let counts = TorrentFilter.counts(for: rows)
    #expect(counts.status[.all] == 4)
    #expect(counts.status[.downloading] == 1)
    #expect(counts.status[.seeding] == 1)
    #expect(counts.status[.paused] == 1)
    #expect(counts.status[.queued] == 0)
    #expect(counts.status[.errors] == 1)
    #expect(counts.categories == ["linux": 1, "films": 1])
    #expect(counts.tags == ["iso": 2, "keep": 1])
    #expect(counts.trackers == ["bt1.archive.org": 1])
    #expect(TorrentCounts.sortedKeys(counts.categories) == ["films", "linux"])
  }

  @Test func readsAndWritesItsTextForm() {
    #expect(TorrentFilter(key: "seeding") == .status(.seeding))
    #expect(TorrentFilter(key: "category:films") == .category("films"))
    #expect(TorrentFilter(key: "tracker:host:8080") == .tracker("host:8080"))
    #expect(TorrentFilter(key: "tag:") == .tag(""))
    #expect(TorrentFilter(key: "nonsense") == .all)
    #expect(TorrentFilter(key: "") == .all)
    for filter in [TorrentFilter.status(.errors), .category("a"), .tag("b:c"), .tracker("")] {
      #expect(TorrentFilter(key: filter.key) == filter)
    }
  }
}

@Suite struct TorrentSortTests {
  let rows = [
    listRow(
      torrent("b", name: "beta") {
        $0.size = 300
        $0.etaSeconds = 60
        $0.queuePosition = 2
        $0.addedAt = testNow.addingTimeInterval(-10)
      }),
    listRow(
      torrent("a", name: "Alpha") {
        $0.size = 100
        $0.queuePosition = 0
      }),
    listRow(
      torrent("c", name: "gamma") {
        $0.size = 300
        $0.etaSeconds = 30
        $0.queuePosition = 1
        $0.completedAt = testNow
        $0.addedAt = testNow.addingTimeInterval(-20)
      }),
  ]

  func order(_ column: TorrentColumn, descending: Bool = false) -> [String] {
    TorrentSort(column: column, descending: descending).sorted(rows).map(\.id)
  }

  @Test func sortsByNameIgnoringCapitals() {
    #expect(order(.name) == ["a", "b", "c"])
    #expect(order(.name, descending: true) == ["c", "b", "a"])
  }

  @Test func tiesGoByNameWhicheverWayRound() {
    #expect(order(.size) == ["a", "b", "c"])
    #expect(order(.size, descending: true) == ["b", "c", "a"])
  }

  @Test func unknownTimesLeftAndUnqueuedGoLast() {
    #expect(order(.eta) == ["c", "b", "a"])
    #expect(order(.queuePosition) == ["c", "b", "a"])
  }

  @Test func neverFinishedComesFirstGoingUp() {
    #expect(order(.completedAt) == ["a", "b", "c"])
  }

  @Test func newestFirstByDefault() {
    #expect(TorrentSort.default.sorted(rows).map(\.id) == ["a", "b", "c"])
  }

  @Test func aHeaderClickTurnsRoundOrStartsTheColumnsOwnWay() {
    let sort = TorrentSort.default
    #expect(sort.clicked(.addedAt) == TorrentSort(column: .addedAt, descending: false))
    #expect(sort.clicked(.size) == TorrentSort(column: .size, descending: true))
    #expect(sort.clicked(.name) == TorrentSort(column: .name, descending: false))
    #expect(sort.clicked(.eta) == TorrentSort(column: .eta, descending: false))
  }

  @Test func worksAsATableSortComparator() {
    var sort = TorrentSort(column: .size, descending: false)
    sort.order = .reverse
    #expect(sort.descending)
    #expect(rows.sorted(using: sort).map(\.id) == ["b", "c", "a"])
  }

  /// By the words the list shows (the Mac's "Verifying" for checking).
  @Test func statusSortsByItsWords() {
    let list = [
      listRow(torrent("1", name: "x") { $0.state = .seeding }),
      listRow(torrent("2", name: "x") { $0.state = .checking }),
      listRow(torrent("3", name: "x") { $0.state = .downloading }),
    ]
    #expect(
      TorrentSort(column: .status, descending: false).sorted(list).map(\.id) == ["3", "1", "2"])
  }

  @Test func columnsCarryTheWebPagesHeaders() {
    #expect(TorrentColumn.downSpeed.header == "Down")
    #expect(TorrentColumn.downSpeed.menuLabel == "Down speed")
    #expect(TorrentColumn.size.alignsRight)
    #expect(!TorrentColumn.name.alignsRight)
    #expect(TorrentColumn.defaultColumns.first == .name)
  }
}
