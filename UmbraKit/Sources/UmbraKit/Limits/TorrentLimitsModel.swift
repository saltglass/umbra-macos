import Foundation
import Observation
import UmbraAPI

/// The torrents a Limits sheet is about, fixed when it opens so a change
/// in the list while it is open can't change what it edits.
public struct LimitsRequest: Identifiable, Equatable, Sendable {
  public let id = UUID()
  public let hashes: [String]
  /// The first torrent's name, for the sheet's heading.
  public let name: String
  /// Each torrent's category ("" for none).
  public let categories: [String]

  public init(rows: [TorrentRow]) {
    hashes = rows.map(\.id)
    name = rows.first?.name ?? ""
    categories = rows.map(\.category)
  }

  public init(hashes: [String], name: String, categories: [String]) {
    self.hashes = hashes
    self.name = name
    self.categories = categories
  }
}

/// The Limits sheet: loads one torrent's own limits (or starts empty for
/// several), keeps what is typed, and saves it. Umbra decides what is
/// allowed; when it refuses, its words are kept in `problems` and
/// `generalProblem` and the sheet stays open.
@MainActor @Observable
public final class TorrentLimitsModel {
  public enum Phase: Equatable, Sendable {
    case loading, ready
    /// Umbra's words for why the torrent's limits couldn't be read.
    case loadFailed(String)
  }

  public let request: LimitsRequest
  public private(set) var phase = Phase.loading
  public private(set) var draft: LimitsDraft
  public private(set) var hints: LimitHints
  /// Waiting for Umbra's answer to Save.
  public private(set) var saving = false
  /// Words under a box: Umbra's own, or "Enter a number."
  public private(set) var refused: [LimitField: String] = [:]
  /// Umbra's words when it refused with no field to blame.
  public private(set) var generalProblem: String?

  @ObservationIgnored private let actions: @MainActor () -> TorrentActions?
  @ObservationIgnored private let locale: Locale

  public init(
    request: LimitsRequest, actions: @escaping @MainActor () -> TorrentActions?,
    locale: Locale = .current
  ) {
    self.request = request
    self.actions = actions
    self.locale = locale
    draft = LimitsDraft(several: request.hashes.count > 1, locale: locale)
    hints = LimitHints(
      mixedCategories: Set(request.categories).count > 1, locale: locale)
  }

  /// A sheet already loaded with fixed values, for pictures of the views.
  public static func fixture(
    request: LimitsRequest, own: Components.Schemas.OwnLimits?, hints: LimitHints,
    locale: Locale = .current
  ) -> TorrentLimitsModel {
    let model = TorrentLimitsModel(request: request, actions: { nil }, locale: locale)
    if let own { model.draft = LimitsDraft(own: own, locale: locale) }
    model.hints = hints
    model.phase = .ready
    return model
  }

  public var count: Int { request.hashes.count }
  public var isSeveral: Bool { count > 1 }

  public var heading: String { "Limits" }

  /// The torrent's name, or how many torrents.
  public var subheading: String {
    isSeveral ? "\(Format.count(count)) torrents" : request.name
  }

  /// What several torrents mean for the boxes. Umbra changes only the
  /// fields it is sent, so an empty box leaves a limit alone.
  public var note: String? {
    isSeveral
      ? "Changes apply to all \(Format.count(count)) torrents; blank fields are left as they are."
      : nil
  }

  public var footer: String {
    isSeveral
      ? "To take a limit away from all of them, use the menu beside its box."
      : "A blank box means no limit of its own: the category's setting, or the global one, applies."
  }

  /// Words under a box: what Umbra refused, else what can't be read yet.
  public func problem(for field: LimitField) -> String? {
    refused[field] ?? (draft.problems[field])
  }

  /// Whether Save can be pressed.
  public var canSave: Bool {
    phase == .ready && !saving && draft.problems.isEmpty
  }

  // MARK: Editing

  public func type(_ text: String, into field: LimitField) {
    draft.type(text, into: field)
    refused[field] = nil
  }

  public func choose(_ choice: LimitsDraft.Choice, for field: LimitField) {
    draft.choose(choice, for: field)
    refused[field] = nil
  }

  public func placeholder(for field: LimitField) -> String {
    hints.placeholder(for: field, in: draft)
  }

  // MARK: Loading

  /// Reads what the sheet shows. For one torrent its own limits are
  /// needed (a failure is shown with Try Again); the category's and the
  /// global goals only fill the grey hints, so a failure there is ignored.
  public func load() async {
    guard let actions = actions() else {
      phase = .loadFailed("Umbra isn't connected.")
      return
    }
    phase = .loading
    var categoryName = Set(request.categories).count == 1 ? request.categories[0] : ""
    if !isSeveral {
      do {
        let limits = try await actions.limits(of: request.hashes[0])
        draft = LimitsDraft(own: limits.own, locale: locale)
        categoryName = limits.category
      } catch {
        phase = .loadFailed(error.message)
        return
      }
    }
    let global = try? await actions.seedingGoals()
    let categories = (try? await actions.categories()) ?? []
    hints = LimitHints(
      global: global,
      category: categories.first { $0.name == categoryName && !categoryName.isEmpty },
      mixedCategories: Set(request.categories).count > 1, locale: locale)
    phase = .ready
  }

  // MARK: Saving

  /// Sends the changes. True once Umbra has them (or nothing was
  /// changed): the sheet then closes. Otherwise the sheet stays and
  /// shows why.
  public func save() async -> Bool {
    guard !saving else { return false }
    guard let changes = draft.torrentChanges() else { return false }
    guard let actions = actions() else {
      generalProblem = "Umbra isn't connected."
      return false
    }
    saving = true
    refused = [:]
    generalProblem = nil
    defer { saving = false }
    do {
      try await actions.setLimits(changes, for: request.hashes)
      return true
    } catch {
      var general: [String] = error.fields.isEmpty ? [error.message] : []
      for (name, message) in error.fields.sorted(by: { $0.key < $1.key }) {
        if let field = LimitField.allCases.first(where: { $0.umbraName == name }) {
          refused[field] = message
        } else {
          general.append(message)
        }
      }
      generalProblem = general.isEmpty ? nil : general.joined(separator: " ")
      return false
    }
  }
}
