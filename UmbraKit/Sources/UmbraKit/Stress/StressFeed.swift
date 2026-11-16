import Foundation
import UmbraAPI

/// A made-up, busy torrent list that needs no Umbra: 100 torrents in every
/// state, and a change every second to about 30 of them (progress, speeds,
/// downloads finishing, pauses and resumes, now and then one added or
/// removed).
///
/// It is for development only: to measure the list, to draw pictures of the
/// views, and to see the window busy. Everything comes from the seed, so
/// the same seed and start time always give exactly the same list and
/// changes.
public struct StressFeed: Sendable {
  public typealias Torrent = Components.Schemas.Torrent

  /// The list as it stands, in the order a snapshot sends it.
  public private(set) var torrents: [Torrent] = []
  /// The revision of the list; each step makes one more.
  public private(set) var rev: Int64 = 1
  /// The made-up clock: the start time plus one second a step.
  public private(set) var now: Date

  private var random: SeededRandom
  private var usedNames: Set<String> = []
  /// Download totals since the feed started, for the status bar.
  private var sessionDown: Int64 = 0
  private var sessionUp: Int64 = 0

  /// How many torrents a new feed has: the size this app is designed for.
  public static let designSize = 100

  /// - Parameters:
  ///   - seed: picks the torrents and every change.
  ///   - count: how many torrents to start with.
  ///   - start: the made-up "now" at the start; dates are made around it.
  public init(seed: UInt64 = 1, count: Int = designSize, start: Date) {
    random = SeededRandom(seed: seed)
    // Whole seconds: the feed's messages carry times to the second, so the
    // list read back from them is exactly this one.
    now = Date(timeIntervalSince1970: start.timeIntervalSince1970.rounded(.down))
    for _ in 0..<count { torrents.append(makeTorrent(fresh: false)) }
  }

  /// The whole list, as the feed's first message.
  public var snapshot: Components.Schemas.TorrentsSnapshot {
    .init(rev: rev, torrents: torrents)
  }

  /// The status bar's totals for the list as it stands.
  public var transfer: Components.Schemas.Transfer {
    .init(
      downSpeed: torrents.reduce(0) { $0 + $1.downSpeed },
      upSpeed: torrents.reduce(0) { $0 + $1.upSpeed },
      downLimit: 0, upLimit: 0, slowMode: false,
      sessionDownloaded: sessionDown, sessionUploaded: sessionUp,
      freeSpace: 412 << 30, lowSpace: 20 << 30, incoming: true, dhtNodes: 1_204, vpn: .none)
  }

  // MARK: One second

  /// Moves the made-up clock on a second and changes about 30 torrents;
  /// returns the change, as the feed's delta message.
  public mutating func step() -> Components.Schemas.TorrentsDelta {
    let from = rev
    now = now.addingTimeInterval(1)
    var changed: [String: Torrent] = [:]
    var removed: [String] = []

    // About 30, picked at random.
    let howMany = min(torrents.count, Int.random(in: 26...34, using: &random))
    var indices = Array(torrents.indices)
    indices.shuffle(using: &random)
    for index in indices.prefix(howMany).sorted() {
      var torrent = torrents[index]
      advance(&torrent)
      torrents[index] = torrent
      changed[torrent.hash] = torrent
    }

    // Now and then one goes or comes, staying near the design size.
    if torrents.count > 90, random.chance(0.04) {
      let gone = torrents.remove(at: Int.random(in: 0..<torrents.count, using: &random))
      changed[gone.hash] = nil
      removed.append(gone.hash)
    }
    if torrents.count < 110, random.chance(0.04) {
      let added = makeTorrent(fresh: true)
      torrents.append(added)
      changed[added.hash] = added
    }

    rev += 1
    // In list order, so the same seed always gives the same message.
    let list = torrents.filter { changed[$0.hash] != nil }
    return .init(from: from, rev: rev, changed: list, removed: removed)
  }

  /// One torrent's second: a few seconds' worth of change, since each is
  /// only touched about one step in three.
  private mutating func advance(_ t: inout Torrent) {
    let elapsed: Int64 = 3
    switch t.state {
    case .downloading:
      if random.chance(0.02) { return pause(&t) }
      t.downSpeed = jitter(t.downSpeed, low: 40_000, high: 25_000_000)
      t.upSpeed = random.chance(0.5) ? jitter(t.upSpeed, low: 0, high: 2_000_000) : 0
      let left = Int64(Double(t.size) * (1 - t.progress))
      let got = min(left, t.downSpeed * elapsed * 8)  // a little quicker than life, to see finishes
      t.downloaded += got
      t.uploaded += t.upSpeed * elapsed
      t.progress = t.size > 0 ? min(1, t.progress + Double(got) / Double(t.size)) : 0
      sessionDown += got
      sessionUp += t.upSpeed * elapsed
      // Done when the last byte arrives (adding fractions never quite reaches 1).
      if got >= left {
        finish(&t)
      } else {
        t.etaSeconds = t.downSpeed > 0 ? (left - got) / t.downSpeed : nil
        t.seeds = max(0, t.seeds + Int.random(in: -2...2, using: &random))
        t.peers = max(0, t.peers + Int.random(in: -3...3, using: &random))
      }
    case .seeding:
      if random.chance(0.02) { return pause(&t) }
      t.upSpeed = random.chance(0.6) ? jitter(t.upSpeed, low: 1_000, high: 5_000_000) : 0
      t.uploaded += t.upSpeed * elapsed
      sessionUp += t.upSpeed * elapsed
      t.seedTimeSeconds += elapsed
      t.ratio = t.downloaded > 0 ? Double(t.uploaded) / Double(t.downloaded) : 0
      t.peers = max(0, t.peers + Int.random(in: -2...2, using: &random))
    case .paused:
      if random.chance(0.08) { start(&t) }
    case .queued:
      if random.chance(0.12) { start(&t) }
    case .checking, .moving:
      t.progress = min(1, t.progress + 0.1)
      if random.chance(0.25) { t.progress >= 1 ? finish(&t) : start(&t) }
    case .fetchingDetails:
      if random.chance(0.2) {
        t.size = Int64.random(in: 300...6_000, using: &random) << 20
        start(&t)
      }
    case .error, .missingFiles, .waitingForVpn, .waitingForSpace:
      if random.chance(0.03) { pause(&t) }
    }
  }

  private mutating func start(_ t: inout Torrent) {
    t.error = nil
    t.spaceWait = nil
    t.queuePosition = 0
    if t.progress >= 1 {
      t.state = .seeding
    } else {
      t.state = .downloading
      t.downSpeed = Int64.random(in: 200_000...8_000_000, using: &random)
      t.seeds = Int.random(in: 1...30, using: &random)
    }
  }

  private mutating func pause(_ t: inout Torrent) {
    t.state = .paused
    t.error = nil
    t.spaceWait = nil
    stopTransfers(&t)
  }

  private func finish(_ t: inout Torrent) {
    t.state = .seeding
    t.progress = 1
    t.downloaded = max(t.downloaded, t.size)
    t.downSpeed = 0
    t.etaSeconds = nil
    t.completedAt = now
  }

  private func stopTransfers(_ t: inout Torrent) {
    t.downSpeed = 0
    t.upSpeed = 0
    t.etaSeconds = nil
    t.seeds = 0
    t.peers = 0
  }

  /// A speed that wanders: up or down by up to a third, within its bounds.
  private mutating func jitter(_ value: Int64, low: Int64, high: Int64) -> Int64 {
    let base = max(value, low + (high - low) / 20)
    let factor = Double.random(in: 0.67...1.33, using: &random)
    return min(high, max(low, Int64(Double(base) * factor)))
  }

  // MARK: Making torrents

  private mutating func makeTorrent(fresh: Bool) -> Torrent {
    let kind = random.pick(StressCatalogue.kinds)
    let name = uniqueName(kind)
    let size = Int64(Int.random(in: kind.sizeMB, using: &random)) << 20
    let state: Components.Schemas.TorrentState =
      fresh
      ? random.weighted([(.fetchingDetails, 2), (.downloading, 3), (.queued, 1)])
      : random.weighted([
        (.downloading, 25), (.seeding, 40), (.paused, 10), (.queued, 8), (.checking, 3),
        (.fetchingDetails, 3), (.error, 3), (.waitingForVpn, 3), (.waitingForSpace, 2),
        (.moving, 1), (.missingFiles, 2),
      ])
    let finished: Bool =
      switch state {
      case .seeding, .missingFiles: true
      case .downloading, .fetchingDetails, .queued, .waitingForSpace: false
      default: random.chance(0.5)
      }
    let progress =
      finished ? 1 : (state == .fetchingDetails ? 0 : Double.random(in: 0...0.97, using: &random))
    // Fresh ones arrive now; the rest were added up to two years ago.
    let age = fresh ? 0 : TimeInterval(Int.random(in: 60...(730 * 86_400), using: &random))
    let addedAt = now.addingTimeInterval(-age)
    let downloaded = Int64(Double(size) * progress)
    let ratio =
      finished
      ? Double.random(in: 0...4, using: &random) : Double.random(in: 0...0.3, using: &random)
    let uploaded = Int64(Double(max(downloaded, 1)) * ratio)
    let category = kind.category
    let tags = kind.tags.filter { _ in random.chance(0.35) }
    let tracker = random.pick(kind.trackers)

    var t = Torrent(
      hash: random.hash(), name: name, size: state == .fetchingDetails ? 0 : size,
      progress: progress, state: state, downSpeed: 0, upSpeed: 0, ratio: ratio, category: category,
      tags: tags, addedAt: addedAt,
      completedAt: finished ? addedAt.addingTimeInterval((age / 10).rounded()) : nil,
      savePath: "/Users/Shared/Downloads" + (category.isEmpty ? "" : "/\(category)"),
      seeds: 0, seedsTotal: Int.random(in: 0...400, using: &random), peers: 0,
      peersTotal: Int.random(in: 0...120, using: &random), downloaded: downloaded,
      uploaded: uploaded,
      seedTimeSeconds: finished ? Int64(age * 0.8) : 0,
      tracker: tracker.isEmpty ? nil : tracker, queuePosition: 0)

    switch state {
    case .downloading:
      t.downSpeed = Int64.random(in: 40_000...20_000_000, using: &random)
      t.upSpeed = random.chance(0.5) ? Int64.random(in: 0...1_500_000, using: &random) : 0
      t.seeds = Int.random(in: 1...40, using: &random)
      t.peers = Int.random(in: 0...25, using: &random)
      t.etaSeconds = Int64(Double(size) * (1 - progress)) / t.downSpeed
    case .seeding:
      t.upSpeed = random.chance(0.4) ? Int64.random(in: 1_000...3_000_000, using: &random) : 0
      t.peers = Int.random(in: 0...12, using: &random)
    case .queued:
      t.queuePosition = Int.random(in: 1...20, using: &random)
    case .error:
      t.error = random.pick(StressCatalogue.errors)
    case .missingFiles:
      t.error = StressCatalogue.missing
    case .paused:
      if finished, random.chance(0.4) { t.error = StressCatalogue.seedGoal }
    case .waitingForSpace:
      let need = Int64(Double(size) * (1 - progress))
      t.spaceWait = .init(
        need: need, free: need / 2, keep: 20 << 30,
        others: random.chance(0.5) ? Int64(Int.random(in: 1...8, using: &random)) << 30 : 0)
    default:
      break
    }
    return t
  }

  /// A name not yet in the list: a title and a variant, numbered if both are taken.
  private mutating func uniqueName(_ kind: StressCatalogue.Kind) -> String {
    let base = random.pick(kind.names) + random.pick(kind.variants)
    var name = base
    var number = 2
    while usedNames.contains(name) {
      name = "\(base) (\(number))"
      number += 1
    }
    usedNames.insert(name)
    return name
  }
}
