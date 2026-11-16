import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import UmbraAPI

/// Every change the main window makes to torrents, sent to Umbra.
///
/// Each call either works or throws an `UmbraError` whose `message` is
/// Umbra's own plain-English explanation, ready to show in an alert. No
/// torrent logic lives here: each call is one request (two for slow mode
/// and editing a tracker, which read the current value first, as the web
/// page does).
///
/// A call with no torrents named does nothing: Umbra requires at least one.
public struct TorrentActions: Sendable {
  let client: Client

  public init(connection: Connection) {
    self.init(connection: connection, transport: URLSessionTransport())
  }

  /// Same, over a transport of the caller's choosing (tests use a fake one).
  public init(connection: Connection, transport: any ClientTransport) {
    client = connection.makeClient(
      transport: transport,
      extraMiddlewares: [ServerErrorMiddleware(), LimitsBodyMiddleware()])
  }

  // MARK: Running and the queue (POST /torrents/actions)

  /// One of the list's plain actions, on several torrents at once.
  public enum Action: String, Sendable, CaseIterable {
    case pause, resume, forceStart, recheck, reannounce
    case queueTop, queueUp, queueDown, queueBottom
  }

  public func perform(_ action: Action, on hashes: [String]) async throws(UmbraError) {
    guard !hashes.isEmpty,
      let payload = Components.Schemas.TorrentAction.actionPayload(rawValue: action.rawValue)
    else { return }
    let output = try await call {
      try await client.torrentAction(body: .json(.init(action: payload, hashes: hashes)))
    }
    guard case .noContent = output else { throw .unexpectedAnswer }
  }

  public func pause(_ hashes: [String]) async throws(UmbraError) {
    try await perform(.pause, on: hashes)
  }
  public func resume(_ hashes: [String]) async throws(UmbraError) {
    try await perform(.resume, on: hashes)
  }
  public func forceStart(_ hashes: [String]) async throws(UmbraError) {
    try await perform(.forceStart, on: hashes)
  }
  public func recheck(_ hashes: [String]) async throws(UmbraError) {
    try await perform(.recheck, on: hashes)
  }
  public func reannounce(_ hashes: [String]) async throws(UmbraError) {
    try await perform(.reannounce, on: hashes)
  }

  // MARK: Removing (POST /torrents/remove)

  /// Removes torrents. With `deleteFiles`, Umbra also deletes what they
  /// downloaded, for good (no Trash), so the window must ask first.
  public func remove(_ hashes: [String], deleteFiles: Bool) async throws(UmbraError) {
    guard !hashes.isEmpty else { return }
    let output = try await call {
      try await client.removeTorrents(
        body: .json(.init(hashes: hashes, deleteFiles: deleteFiles)))
    }
    guard case .noContent = output else { throw .unexpectedAnswer }
  }

  // MARK: Adding (the Add sheet: POST /torrents, /torrents/inspect)

  /// What to look at or add: a .torrent file's bytes, a magnet link, or
  /// the web address of a .torrent file. Umbra does all the reading.
  public enum AddInput: Equatable, Sendable {
    case torrentFile(Data)
    case magnet(String)
    case url(String)
  }

  /// What a torrent is, before adding it. Nothing is added. For a magnet
  /// link (or an address that leads to one) Umbra starts fetching its
  /// details (`waiting` is then true) until it is added or `cancelWaiting`.
  public func inspect(_ input: AddInput) async throws(UmbraError)
    -> Components.Schemas
    .TorrentPreview
  {
    let body: Components.Schemas.InspectTorrent =
      switch input {
      case .torrentFile(let data): .init(torrentFile: .init(data))
      case .magnet(let link): .init(magnet: link, fetchDetails: true)
      case .url(let address): .init(url: address, fetchDetails: true)
      }
    let output = try await call { try await client.inspectTorrent(body: .json(body)) }
    guard case .ok(let ok) = output, case .json(let preview) = ok.body else {
      throw .unexpectedAnswer
    }
    return preview
  }

  /// A magnet link waiting in the Add sheet, with its files once they arrive.
  public func waitingTorrent(_ hash: String) async throws(UmbraError)
    -> Components.Schemas
    .TorrentPreview
  {
    let output = try await call { try await client.getWaitingTorrent(path: .init(hash: hash)) }
    guard case .ok(let ok) = output, case .json(let preview) = ok.body else {
      throw .unexpectedAnswer
    }
    return preview
  }

  /// Stops waiting on a magnet link (the sheet closed without adding it).
  /// Never removes a torrent that was added.
  public func cancelWaiting(_ hash: String) async throws(UmbraError) {
    let output = try await call {
      try await client.cancelWaitingTorrent(path: .init(hash: hash))
    }
    guard case .noContent = output else { throw .unexpectedAnswer }
  }

  /// Adds a torrent with the sheet's choices. Only a magnet link or a
  /// .torrent file can be added (a web address is inspected first, which
  /// gives one of them). `filePriorities` is one per file, in the
  /// torrent's order; nil downloads everything. An empty category is none.
  public func add(
    _ input: AddInput, category: String = "", tags: [String] = [], paused: Bool = false,
    filePriorities: [Components.Schemas.FilePriority]? = nil
  ) async throws(UmbraError) -> Components.Schemas.AddResult {
    var body = Components.Schemas.AddTorrent(
      category: category.isEmpty ? nil : category, tags: tags, paused: paused,
      filePriorities: filePriorities)
    switch input {
    case .torrentFile(let data): body.torrentFile = .init(data)
    case .magnet(let link): body.magnet = link
    case .url: throw .unexpectedAnswer
    }
    let output = try await call { try await client.addTorrent(body: .json(body)) }
    guard case .ok(let ok) = output, case .json(let result) = ok.body else {
      throw .unexpectedAnswer
    }
    return result
  }

  /// Where new torrents are saved: the default folder and each
  /// category's (Settings → Downloads), for the sheet's "Save to" line.
  public func saveFolders() async throws(UmbraError) -> SaveFolders {
    let output = try await call { try await client.getDownloadsSettings() }
    guard case .ok(let ok) = output, case .json(let settings) = ok.body else {
      throw .unexpectedAnswer
    }
    return SaveFolders(settings)
  }

  // MARK: Category and tags

  /// Sets the category; "" takes it away. Files stay where they are.
  public func setCategory(_ category: String, for hashes: [String]) async throws(UmbraError) {
    guard !hashes.isEmpty else { return }
    let output = try await call {
      try await client.setTorrentsCategory(body: .json(.init(hashes: hashes, category: category)))
    }
    guard case .noContent = output else { throw .unexpectedAnswer }
  }

  /// Adds and takes away tags; other tags stay. A new tag needs no setting up.
  public func changeTags(
    add: [String] = [], remove: [String] = [], for hashes: [String]
  ) async throws(UmbraError) {
    guard !hashes.isEmpty, !(add.isEmpty && remove.isEmpty) else { return }
    let output = try await call {
      try await client.setTorrentsTags(
        body: .json(
          .init(hashes: hashes, add: add.isEmpty ? nil : add, remove: remove.isEmpty ? nil : remove)
        ))
    }
    guard case .noContent = output else { throw .unexpectedAnswer }
  }

  // MARK: Trackers

  /// The torrent's trackers and how each is doing.
  public func trackers(of hash: String) async throws(UmbraError) -> Components.Schemas.TrackerList {
    let output = try await call { try await client.getTorrentTrackers(path: .init(hash: hash)) }
    guard case .ok(let ok) = output, case .json(let list) = ok.body else {
      throw .unexpectedAnswer
    }
    return list
  }

  /// Adds trackers; each goes in a tier of its own, after the others.
  public func addTrackers(_ urls: [String], to hash: String) async throws(UmbraError) {
    guard !urls.isEmpty else { return }
    let output = try await call {
      try await client.addTorrentTrackers(path: .init(hash: hash), body: .json(.init(urls: urls)))
    }
    guard case .noContent = output else { throw .unexpectedAnswer }
  }

  /// Replaces the whole tracker list, in tiers (lower tiers are asked first).
  public func setTrackers(_ tiers: [[String]], of hash: String) async throws(UmbraError) {
    let output = try await call {
      try await client.setTorrentTrackers(path: .init(hash: hash), body: .json(.init(tiers: tiers)))
    }
    guard case .noContent = output else { throw .unexpectedAnswer }
  }

  /// Changes one tracker's address, keeping its tier.
  public func editTracker(_ old: String, to new: String, of hash: String) async throws(UmbraError) {
    let tiers = Self.tiers(of: try await trackers(of: hash)).map { tier in
      tier.map { $0 == old ? new : $0 }
    }
    try await setTrackers(tiers, of: hash)
  }

  /// Takes trackers away.
  public func removeTrackers(_ urls: [String], of hash: String) async throws(UmbraError) {
    let gone = Set(urls)
    let tiers = Self.tiers(of: try await trackers(of: hash)).map {
      $0.filter { !gone.contains($0) }
    }
    try await setTrackers(tiers, of: hash)
  }

  /// The list's addresses grouped by tier, lowest tier first.
  static func tiers(of list: Components.Schemas.TrackerList) -> [[String]] {
    let byTier = Dictionary(grouping: list.trackers, by: \.tier)
    return byTier.keys.sorted().map { tier in byTier[tier, default: []].map(\.url) }
  }

  // MARK: Files

  /// Sets some files' priorities (by index); others keep theirs. `.skip`
  /// doesn't download a file.
  public func setFilePriorities(
    _ priorities: [Int: Components.Schemas.FilePriority], of hash: String
  ) async throws(UmbraError) {
    guard !priorities.isEmpty else { return }
    let files = priorities.keys.sorted().map {
      Components.Schemas.FilePriorities.filesPayloadPayload(index: $0, priority: priorities[$0]!)
    }
    let output = try await call {
      try await client.setTorrentFilePriorities(
        path: .init(hash: hash), body: .json(.init(files: files)))
    }
    guard case .noContent = output else { throw .unexpectedAnswer }
  }

  // MARK: Sharing

  /// The torrent's magnet link, for "Copy magnet link".
  public func magnetLink(of hash: String) async throws(UmbraError) -> String {
    let output = try await call { try await client.getTorrentMagnet(path: .init(hash: hash)) }
    guard case .ok(let ok) = output, case .json(let link) = ok.body else {
      throw .unexpectedAnswer
    }
    return link.magnet
  }

  /// The .torrent file's bytes, for "Export .torrent".
  public func torrentFile(of hash: String) async throws(UmbraError) -> Data {
    try await call {
      let output = try await client.exportTorrentFile(path: .init(hash: hash))
      guard case .ok(let ok) = output, case .application_x_hyphen_bittorrent(let body) = ok.body
      else { throw UmbraError.unexpectedAnswer }
      // A .torrent file is small; 64 MB is far more than any real one.
      return try await Data(collecting: body, upTo: 64 << 20)
    }
  }

  // MARK: Slow mode

  /// Turns slow mode (the alternative speed limits) on or off, keeping
  /// every other speed setting as it is. Returns the settings now stored.
  @discardableResult
  public func setSlowMode(_ on: Bool) async throws(UmbraError) -> Components.Schemas.SpeedSettings {
    let current = try await call { try await client.getSpeedSettings() }
    guard case .ok(let ok) = current, case .json(var settings) = ok.body else {
      throw .unexpectedAnswer
    }
    settings.slowMode = on
    let saved = try await call { try await client.putSpeedSettings(body: .json(settings)) }
    guard case .ok(let done) = saved, case .json(let stored) = done.body else {
      throw .unexpectedAnswer
    }
    return stored
  }

  // MARK: Menus

  /// The names of the categories set up in Settings → Downloads, for the
  /// Category menu.
  public func categoryNames() async throws(UmbraError) -> [String] {
    let output = try await call { try await client.getDownloadsSettings() }
    guard case .ok(let ok) = output, case .json(let settings) = ok.body else {
      throw .unexpectedAnswer
    }
    return settings.categories.map(\.name)
  }

  // MARK: Reading (the inspector)

  /// One torrent, as the list shows it.
  public func torrent(hash: String) async throws(UmbraError) -> Components.Schemas.Torrent {
    let output = try await call { try await client.getTorrent(path: .init(hash: hash)) }
    guard case .ok(let ok) = output, case .json(let torrent) = ok.body else {
      throw .unexpectedAnswer
    }
    return torrent
  }

  /// The peers the torrent is connected to (none while it isn't running).
  public func peers(of hash: String) async throws(UmbraError) -> [Components.Schemas.Peer] {
    let output = try await call { try await client.getTorrentPeers(path: .init(hash: hash)) }
    guard case .ok(let ok) = output, case .json(let list) = ok.body else {
      throw .unexpectedAnswer
    }
    return list.peers
  }

  /// The torrent's files with progress and priority, in the torrent's own
  /// order. Empty while a magnet link is still fetching its details.
  public func files(of hash: String) async throws(UmbraError) -> [Components.Schemas.TorrentFile] {
    let output = try await call { try await client.getTorrentFiles(path: .init(hash: hash)) }
    guard case .ok(let ok) = output, case .json(let list) = ok.body else {
      throw .unexpectedAnswer
    }
    return list.files
  }

  // MARK: VPN

  /// Asks Umbra to look at the VPN again now (GET /vpn?refresh=true; Umbra
  /// itself allows this at most once in 30 seconds and otherwise answers
  /// with what it last found). Umbra reconnects by itself: this only asks
  /// it to re-check and returns the state it reports.
  public func checkVpnAgain() async throws(UmbraError) -> Components.Schemas.VpnStatus {
    let output = try await call { try await client.getVpn(query: .init(refresh: true)) }
    guard case .ok(let ok) = output, case .json(let status) = ok.body else {
      throw .unexpectedAnswer
    }
    return status
  }

  // MARK: Errors

  /// Runs one request, turning whatever goes wrong into an `UmbraError`.
  func call<T>(_ request: () async throws -> T) async throws(UmbraError) -> T {
    try await callUmbra(request)
  }
}
