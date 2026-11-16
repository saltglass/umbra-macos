import Foundation
import Observation
import UmbraAPI

/// The Create Torrent sheet: what is being shared, what Umbra says it
/// would hold, the options, making the torrent and following its progress.
///
/// Umbra does all the work. This asks it for a preview, sends the options,
/// and shows the answers. It never reads the files itself.
///
/// How it goes:
/// 1. A file or folder is chosen. Umbra is asked for a preview.
/// 2. Create is allowed once a preview has come back (and not before).
/// 3. Umbra queues the torrent and reads every file. The live feed sends
///    its record about once a second (`receive(creations:)`).
/// 4. When it is made, the .torrent file can be saved. If it started
///    seeding, the new torrent is selected in the list.
/// 5. When the sheet closes, whatever record it made is removed from
///    Umbra's list of creations (this also cancels one still being made).
@MainActor @Observable
public final class CreateTorrentModel {
  public typealias Preview = Components.Schemas.CreationPreview
  public typealias Creation = Components.Schemas.Creation

  // MARK: Pieces of the sheet

  /// What Umbra said about the chosen file or folder.
  public enum PreviewState: Equatable, Sendable {
    case none
    case looking
    case ready(Preview)
    /// Umbra's own words, shown under "What to share".
    case refused(String)
  }

  /// A piece size to choose: Automatic, or a power of two from 16 KB to 64 MB.
  public struct PieceSize: Hashable, Sendable, Identifiable {
    /// In bytes; 0 is Automatic.
    public let bytes: Int64
    public var id: Int64 { bytes }
    public static let automatic = PieceSize(bytes: 0)
    /// Every size Umbra accepts, smallest first.
    public static let all: [PieceSize] = (14...26).map { PieceSize(bytes: Int64(1) << $0) }
    public var title: String { bytes == 0 ? "Automatic" : Self.text(bytes) }

    /// "16 MB", "512 KB": piece sizes are powers of two, so they read whole.
    public static func text(_ bytes: Int64) -> String {
      if bytes >= 1 << 20, bytes % (1 << 20) == 0 { return "\(bytes >> 20) MB" }
      if bytes >= 1 << 10, bytes % (1 << 10) == 0 { return "\(bytes >> 10) KB" }
      return Format.bytes(bytes)
    }
  }

  /// The fields Umbra can refuse, by the names it uses.
  public enum Field: String, Sendable, CaseIterable {
    case path, trackers, comment, source, pieceLength
  }

  /// Where the sheet is, for its buttons and wording.
  public enum Phase: Equatable, Sendable {
    /// Choosing and setting options.
    case editing
    /// Create was pressed and Umbra hasn't answered yet.
    case starting
    /// Queued: waiting for the torrent before it, or just starting.
    case queued(behindAnother: Bool)
    /// Umbra is reading the files.
    case reading(read: Int64, size: Int64)
    /// Made.
    case done
    /// Umbra could not make it (its words).
    case failed(String)
    /// Umbra no longer has it (dismissed, or Umbra restarted).
    case gone
  }

  /// The footer's plain statement while "Start seeding" is on.
  public static let seedingNote =
    "Umbra seeds the files from where they are. Moving or deleting them stops the torrent working."

  // MARK: What the person chose

  /// The full path chosen; "" before anything is.
  public private(set) var path = ""
  public private(set) var previewState: PreviewState = .none

  public var trackersText = "" {
    didSet { if trackersText != oldValue { fieldProblems[.trackers] = nil } }
  }
  public var comment = "" {
    didSet { if comment != oldValue { fieldProblems[.comment] = nil } }
  }
  public var source = "" {
    didSet { if source != oldValue { fieldProblems[.source] = nil } }
  }
  public var pieceSize: PieceSize = .automatic {
    didSet {
      guard pieceSize != oldValue else { return }
      fieldProblems[.pieceLength] = nil
      if !path.isEmpty { requestPreview() }
    }
  }
  /// Added to the list, seeding, when it is made. On unless turned off.
  public var startSeeding = true
  /// What the person chose for "Private torrent" by hand; nil until then.
  private var privateChoice: Bool?

  /// Private torrents need trackers, so the box starts ticked once there
  /// are some (as on Umbra's web page), until the person chooses.
  public var isPrivate: Bool {
    get { privateChoice ?? !trackerTiers.isEmpty }
    set { privateChoice = newValue }
  }

  /// The tracker box, read as tiers.
  public var trackerTiers: [[String]] { TrackerText.tiers(from: trackersText) }

  // MARK: Refusals

  /// Umbra's words for what it turned down, by field.
  public private(set) var fieldProblems: [Field: String] = [:]
  /// A refusal that is not about one field (or the connection failing).
  public private(set) var generalFailure: String?
  /// Why saving the .torrent file failed.
  public private(set) var saveFailure: String?
  public private(set) var isSaving = false

  /// What to show under "What to share": a refused preview, or a refusal
  /// of the path when creating.
  public var pathProblem: String? {
    if case .refused(let words) = previewState { return words }
    return fieldProblems[.path]
  }

  public func problem(_ field: Field) -> String? {
    field == .path ? pathProblem : fieldProblems[field]
  }

  // MARK: Making

  private var stage: Stage = .editing
  private enum Stage { case editing, starting, making }
  /// The record from Umbra's answer, then from the live feed.
  private var latest: Creation?
  /// The feed has listed this torrent at least once.
  private var seenInFeed = false
  private var behindAnother = false
  private var wentMissing = false
  private var selectedNew = false

  public var phase: Phase {
    switch stage {
    case .editing: return .editing
    case .starting: return .starting
    case .making:
      if wentMissing { return .gone }
      guard let latest else { return .queued(behindAnother: false) }
      switch latest.state {
      case .queued: return .queued(behindAnother: behindAnother)
      case .reading: return .reading(read: latest.read, size: latest.size)
      case .done: return .done
      case .failed:
        return .failed(latest.error ?? "Umbra couldn't make the torrent.")
      }
    }
  }

  /// The torrent made (or being made), as Umbra last described it.
  public var creation: Creation? { stage == .making ? latest : nil }

  /// Options and the choice can be changed.
  public var isEditable: Bool { stage == .editing }

  /// Create can be pressed: a preview came back, and nothing is under way.
  public var canCreate: Bool {
    guard stage == .editing, case .ready = previewState else { return false }
    return true
  }

  /// Cancel is shown as "Cancel" while making, and the bar can move.
  public var isMaking: Bool {
    switch phase {
    case .starting, .queued, .reading: return true
    default: return false
    }
  }

  /// 0...1 for the progress bar; nil when it can't say yet.
  public var fraction: Double? {
    guard case .reading(let read, let size) = phase, size > 0 else { return nil }
    return min(max(Double(read) / Double(size), 0), 1)
  }

  /// One line under the bar.
  public var progressLine: String {
    switch phase {
    case .starting: "Sending it to Umbra…"
    case .queued(let behind):
      behind ? "Waiting for the torrent before it to be made." : "Starting…"
    case .reading(let read, let size):
      "Reading every file to work out its pieces: \(Format.bytes(read)) of \(Format.bytes(size))."
    default: ""
    }
  }

  /// What the preview says, as one line: "12 files, 41.3 GB, 2,644 pieces of 16 MB".
  public static func summary(files: Int, size: Int64, pieces: Int, pieceLength: Int64) -> String {
    "\(Format.count(files)) \(files == 1 ? "file" : "files"), \(Format.bytes(size)), "
      + "\(Format.count(pieces)) \(pieces == 1 ? "piece" : "pieces") of \(PieceSize.text(pieceLength))"
  }

  public var previewSummary: String? {
    guard case .ready(let p) = previewState else { return nil }
    return Self.summary(files: p.files, size: p.size, pieces: p.pieces, pieceLength: p.pieceLength)
  }

  /// The name to show for the choice: Umbra's, once it has said one.
  public var chosenName: String {
    if case .ready(let p) = previewState, let name = p.name, !name.isEmpty { return name }
    return (path as NSString).lastPathComponent
  }

  /// The made torrent, one line (done).
  public var madeSummary: String? {
    guard let c = creation else { return nil }
    return Self.summary(files: c.files, size: c.size, pieces: c.pieces, pieceLength: c.pieceLength)
      + (c._private ? ", private" : "")
  }

  /// Done, and Umbra started seeding it.
  public var isSeeding: Bool { phase == .done && creation?.seeding == true }

  /// Done, and it was asked to seed but couldn't (Umbra's words).
  public var seedingProblem: String? {
    guard phase == .done, let c = creation, !c.seeding, startedWithSeeding else { return nil }
    return c.error
  }
  private var startedWithSeeding = false

  /// The name the save panel offers.
  public var suggestedFileName: String {
    let base = creation?.name ?? chosenName
    let clean = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(
      of: ":", with: "-")
    return (clean.isEmpty ? "torrent" : clean) + ".torrent"
  }

  // MARK: Setting up

  @ObservationIgnored private let actions: CreateTorrentActions
  @ObservationIgnored private let select: @MainActor ([String]) -> Void
  @ObservationIgnored private var previewTask: Task<Void, Never>?
  @ObservationIgnored private var previewToken = 0
  @ObservationIgnored private var closed = false

  /// - Parameters:
  ///   - actions: the calls to Umbra.
  ///   - select: selects a torrent in the main list (it is called with the
  ///     new torrent's hash once Umbra has started seeding it).
  public init(
    actions: CreateTorrentActions, select: @escaping @MainActor ([String]) -> Void = { _ in }
  ) {
    self.actions = actions
    self.select = select
  }

  // MARK: Choosing

  /// A file or folder was chosen (open panel or drop). Asks Umbra what it
  /// would hold. Ignored while a torrent is being made.
  public func choose(url: URL) {
    guard stage == .editing, url.isFileURL else { return }
    path = url.path
    fieldProblems[.path] = nil
    generalFailure = nil
    requestPreview()
  }

  private func requestPreview() {
    previewTask?.cancel()
    previewToken += 1
    let token = previewToken
    let path = path
    let length: Int64? = pieceSize.bytes == 0 ? nil : pieceSize.bytes
    previewState = .looking
    previewTask = Task { [actions] in
      do throws(UmbraError) {
        let preview = try await actions.preview(path: path, pieceLength: length)
        guard token == self.previewToken, !Task.isCancelled else { return }
        self.previewState = .ready(preview)
      } catch {
        guard token == self.previewToken, !Task.isCancelled else { return }
        // Umbra's words, whichever field it names: the choice is what failed.
        self.previewState = .refused(error.fields[Field.path.rawValue] ?? error.message)
        if let words = error.fields[Field.pieceLength.rawValue] {
          self.fieldProblems[.pieceLength] = words
        }
      }
    }
  }

  // MARK: Creating

  /// What is sent to Umbra to make the torrent.
  func request() -> Components.Schemas.CreateTorrent {
    let tiers = trackerTiers
    let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
    return .init(
      path: path, trackers: tiers.isEmpty ? nil : tiers, _private: isPrivate,
      comment: trimmedComment.isEmpty ? nil : trimmedComment,
      source: trimmedSource.isEmpty ? nil : trimmedSource,
      pieceLength: pieceSize.bytes == 0 ? nil : pieceSize.bytes, seed: startSeeding)
  }

  /// Sends it to Umbra. A refusal is shown under the field it names; the
  /// sheet keeps everything that was entered.
  public func create() async {
    guard canCreate else { return }
    stage = .starting
    fieldProblems = [:]
    generalFailure = nil
    let wanted = request()
    startedWithSeeding = startSeeding
    do {
      let made = try await actions.create(wanted)
      if closed {
        // The sheet went away while Umbra was answering: don't leave it.
        try? await actions.remove(made.id)
        return
      }
      latest = made
      seenInFeed = false
      wentMissing = false
      behindAnother = false
      selectedNew = false
      stage = .making
      noticeDone()
    } catch {
      stage = .editing
      var general: [String] = []
      for (name, words) in error.fields.sorted(by: { $0.key < $1.key }) {
        if let field = Field(rawValue: name) {
          fieldProblems[field] = words
        } else {
          general.append(words)
        }
      }
      if error.fields.isEmpty { general = [error.message] }
      generalFailure = general.isEmpty ? nil : general.joined(separator: " ")
    }
  }

  // MARK: Progress

  /// The live feed's list of torrents being made (about once a second
  /// while one is). Finds this sheet's own by its id.
  public func receive(creations list: [Creation]?) {
    guard stage == .making, let id = latest?.id, let list else { return }
    behindAnother = list.contains { $0.id != id && $0.state == .reading }
    if let mine = list.first(where: { $0.id == id }) {
      latest = mine
      seenInFeed = true
      noticeDone()
    } else if seenInFeed {
      wentMissing = true
    }
  }

  /// When it is made and seeding, select the new torrent in the list (once).
  private func noticeDone() {
    guard let c = latest, c.state == .done, c.seeding, !selectedNew, let hash = c.hash else {
      return
    }
    selectedNew = true
    select([hash])
  }

  // MARK: Failing, cancelling, closing

  /// After a failure: back to the options, nothing lost.
  public func tryAgain() async {
    guard stage == .making else { return }
    await removeRecord()
    stage = .editing
  }

  /// The Cancel button: stops a torrent being made (Umbra stops reading
  /// within a moment and leaves nothing behind) and removes its record.
  /// The view then closes the sheet.
  public func cancel() async {
    await close()
  }

  /// The sheet is going away: lets go of everything it asked Umbra for.
  /// Safe to call more than once.
  public func close() async {
    closed = true
    previewTask?.cancel()
    previewToken += 1
    await removeRecord()
  }

  private func removeRecord() async {
    guard let id = latest?.id else { return }
    latest = nil
    // Umbra may have forgotten it already (404): nothing more to do then.
    try? await actions.remove(id)
  }

  // MARK: Saving the .torrent file

  /// Fetches the .torrent file from Umbra and writes it to `url`.
  public func saveTorrentFile(to url: URL) async {
    guard phase == .done, let id = creation?.id, !isSaving else { return }
    isSaving = true
    saveFailure = nil
    defer { isSaving = false }
    do {
      let data = try await actions.torrentFile(id)
      try data.write(to: url, options: .atomic)
    } catch let error as UmbraError {
      saveFailure = error.message
    } catch {
      saveFailure = "The file couldn't be saved: \(error.localizedDescription)"
    }
  }

  // MARK: Pictures

  /// Shows the sheet as if these things had happened, without asking
  /// Umbra anything (for `just snapshot`).
  public func showFixture(
    path: String, preview: PreviewState, creation: Creation? = nil,
    problems: [Field: String] = [:], startedWithSeeding: Bool = true
  ) {
    self.path = path
    previewState = preview
    fieldProblems = problems
    self.startedWithSeeding = startedWithSeeding
    if let creation {
      latest = creation
      seenInFeed = true
      stage = .making
    }
  }
}
