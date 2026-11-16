import Foundation
import Observation
import OpenAPIRuntime
import OpenAPIURLSession
import UmbraAPI

/// What the Logs window shows, and every rule behind it.
///
/// Opening it loads Umbra's recent lines, then follows the live stream.
/// Lines that come both ways are shown once. At most 5,000 are kept; the
/// oldest go first. If the stream drops it is opened again quietly, asking
/// for the lines after the newest one held, so none are lost or doubled.
///
/// The filters work on the lines held here. Umbra keeps the same 5,000
/// lines, so this matches what asking Umbra would give, and the live
/// stream arrives unfiltered anyway. Clear empties this window's list
/// only; Umbra's log is never touched.
///
/// If a line holds the app's current credential, it is replaced with "•••"
/// before it is kept (so shown, searched, copied and saved text are all clean).
@MainActor @Observable
public final class LogsModel {
  /// The most lines kept.
  public static let capacity = 5000

  public enum Phase: Sendable, Equatable {
    /// Umbra isn't running (or turned the app's credential away).
    case notConnected
    /// Asking for the recent lines.
    case loading
    /// Showing lines and following new ones.
    case live
    /// Umbra stopped answering; trying again.
    case reconnecting
  }

  public private(set) var phase: Phase = .notConnected
  /// Every line held, oldest first.
  public private(set) var lines: [LogLine] = []

  public var levelFilter: LogLevelFilter = .all
  public var searchText = ""
  /// New lines keep the table scrolled to the end. The window turns it off
  /// when the person scrolls up, and on again at the bottom.
  public var isFollowing = true

  @ObservationIgnored private var secret = ""
  @ObservationIgnored private var service: LogsService?
  @ObservationIgnored private var task: Task<Void, Never>?
  /// The highest line number seen, cleared lines included.
  @ObservationIgnored private var newestSeq: Int64?
  @ObservationIgnored private var generation = 0

  @ObservationIgnored private let transport: any ClientTransport
  @ObservationIgnored private let source: any FeedByteSource
  @ObservationIgnored private let sleep: FeedClient.Sleep
  @ObservationIgnored private let timeZone: TimeZone

  /// - Parameters:
  ///   - transport: how requests are sent (tests use a fake one).
  ///   - source: where the stream's bytes come from (tests use a fake one).
  ///   - sleep: how to wait between attempts (tests don't really wait).
  public init(
    transport: any ClientTransport = URLSessionTransport(),
    source: any FeedByteSource = URLSessionByteSource(),
    sleep: @escaping FeedClient.Sleep = { try await Task.sleep(for: $0) },
    timeZone: TimeZone = .current
  ) {
    self.transport = transport
    self.source = source
    self.sleep = sleep
    self.timeZone = timeZone
  }

  isolated deinit { task?.cancel() }

  /// A model showing fixed lines and nothing else: no connection is made.
  /// For pictures of the window.
  public static func fixture(lines: [LogLine], phase: Phase = .live) -> LogsModel {
    let model = LogsModel()
    model.lines = lines
    model.phase = phase
    return model
  }

  // MARK: What is shown

  /// True when a level or search narrows the list.
  public var isFiltered: Bool { levelFilter != .all || !trimmedSearch.isEmpty }

  private var trimmedSearch: String {
    searchText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// The lines that pass the level and search, oldest first.
  public var visibleLines: [LogLine] {
    guard isFiltered else { return lines }
    let search = trimmedSearch
    return lines.filter {
      levelFilter.includes($0.level) && (search.isEmpty || $0.matches(search))
    }
  }

  /// The bottom line of the window: "N lines", or "N of M shown" when filtered.
  public var statusText: String {
    let total = lines.count
    guard isFiltered else { return Self.lineCount(total) }
    return "\(visibleLines.count.formatted()) of \(total.formatted()) shown"
  }

  /// A small note beside the status text; nil when all is well.
  public var statusNote: String? {
    phase == .reconnecting ? "Reconnecting…" : nil
  }

  private static func lineCount(_ n: Int) -> String {
    n == 1 ? "1 line" : "\(n.formatted()) lines"
  }

  /// Why the table isn't showing lines, in plain words; nil when it is.
  public var emptyMessage: String? {
    guard visibleLines.isEmpty else { return nil }
    switch phase {
    case .notConnected: return nil
    case .loading: return "Loading…"
    case .live, .reconnecting:
      if lines.isEmpty { return "No log lines yet." }
      return "No lines match."
    }
  }

  // MARK: Opening and closing

  /// Opens the window's log: loads the recent lines, then follows the
  /// stream. With no connection, it says so and does nothing else.
  public func open(connection: Connection?) {
    close()
    lines = []
    newestSeq = nil
    guard let connection else {
      phase = .notConnected
      return
    }
    secret = connection.credential.secret
    service = LogsService(connection: connection, transport: transport)
    phase = .loading
    let generation = self.generation
    task = Task { [weak self] in
      await self?.run(connection: connection, generation: generation)
    }
  }

  /// Closes the stream (the window closed, or Umbra went away).
  public func close() {
    generation += 1
    task?.cancel()
    task = nil
    service = nil
    secret = ""
    phase = .notConnected
  }

  private func run(connection: Connection, generation: Int) async {
    guard let service else { return }
    var backoff = FeedBackoff()
    while true {
      do {
        let page = try await service.recent(limit: Self.capacity)
        guard self.generation == generation else { return }
        for entry in page.entries { add(entry) }
        phase = .live
        break
      } catch {
        guard self.generation == generation, !Task.isCancelled else { return }
        phase = .reconnecting
        do { try await sleep(backoff.next()) } catch { return }
        guard self.generation == generation else { return }
      }
    }

    let client = LogStreamClient(connection: connection, source: source, sleep: sleep)
    let updates = client.updates(after: { [weak self] in await self?.newestSeq })
    for await update in updates {
      guard self.generation == generation else { return }
      switch update {
      case .opened: phase = .live
      case .line(let entry): add(entry)
      case .dropped: phase = .reconnecting
      case .refused: phase = .notConnected
      }
    }
  }

  /// Keeps a line unless it was seen already (the first load and the
  /// stream can both carry it), dropping the oldest above the limit.
  private func add(_ entry: Components.Schemas.LogEntry) {
    if let newestSeq, entry.seq <= newestSeq { return }
    newestSeq = entry.seq
    lines.append(LogLine(entry, hiding: secret))
    if lines.count > Self.capacity { lines.removeFirst(lines.count - Self.capacity) }
  }

  // MARK: The toolbar

  /// The person scrolled the table. Scrolling up away from the end pauses
  /// following; scrolling back to the end resumes it (as Console does).
  public func personScrolled(atEnd: Bool) {
    if isFollowing != atEnd { isFollowing = atEnd }
  }

  /// Empties the window's list. Umbra's log is not touched, and cleared
  /// lines don't come back when the stream reopens.
  public func clear() {
    lines = []
  }

  /// The lines with these numbers as plain text, in list order, one per
  /// line, for copying.
  public func copyText(for ids: Set<Int64>) -> String {
    lines.filter { ids.contains($0.id) }
      .map { $0.plainText(timeZone: timeZone) }
      .joined(separator: "\n")
  }

  // MARK: Saving

  /// The name offered in the save panel.
  public func suggestedFileName(now: Date = .now) -> String {
    "umbra-logs-\(LogRedaction.stamp(now, timeZone: timeZone).prefix(10)).txt"
  }

  /// Asks Umbra for its log file (with the level and search now chosen)
  /// and returns it, with the credential hidden.
  public func downloadLogs() async throws(UmbraError) -> Data {
    guard let service else {
      throw UmbraError(code: "not_connected", message: "Umbra isn't connected.")
    }
    let search = trimmedSearch
    let data = try await service.download(
      levels: levelFilter.levelsQuery, search: search.isEmpty ? nil : search)
    let secret = secret
    guard !secret.isEmpty else { return data }
    let text = String(decoding: data, as: UTF8.self)
    return Data(LogRedaction.hide(secret, in: text).utf8)
  }
}
