import Foundation
import UmbraAPI

/// One of the limits a torrent or a category can have of its own.
public enum LimitField: String, CaseIterable, Sendable, Identifiable {
  case downloadLimit, uploadLimit, ratio, seedingTime, inactiveTime

  public var id: String { rawValue }

  /// The speeds, then the seed goals.
  public static let speeds: [LimitField] = [.downloadLimit, .uploadLimit]
  public static let goals: [LimitField] = [.ratio, .seedingTime, .inactiveTime]

  /// Umbra's name for the field, which its refusals use to say which one
  /// is at fault.
  public var umbraName: String {
    switch self {
    case .downloadLimit: "downloadLimitKBs"
    case .uploadLimit: "uploadLimitKBs"
    case .ratio: "ratio"
    case .seedingTime: "seedingMinutes"
    case .inactiveTime: "inactiveMinutes"
    }
  }

  public var title: String {
    switch self {
    case .downloadLimit: "Download limit"
    case .uploadLimit: "Upload limit"
    case .ratio: "Seed ratio"
    case .seedingTime: "Seeding time"
    case .inactiveTime: "Inactive for"
    }
  }

  /// A line saying what the field does (the Seeding page's wording).
  public var help: String {
    switch self {
    case .downloadLimit: "Most it will download at once."
    case .uploadLimit: "Most it will upload at once."
    case .ratio: "Uploaded divided by downloaded."
    case .seedingTime: "How long it has seeded in all."
    case .inactiveTime: "Seeding with nothing uploaded."
    }
  }

  /// After the box.
  public var unit: String? {
    switch self {
    case .downloadLimit, .uploadLimit: "MB/s"
    case .ratio: nil
    case .seedingTime: "hours"
    case .inactiveTime: "min"
    }
  }

  public var isGoal: Bool { Self.goals.contains(self) }

  /// The title in the inspector, where it is a row on its own.
  public var summaryTitle: String {
    switch self {
    case .downloadLimit, .uploadLimit: title
    case .ratio: "Seed ratio goal"
    case .seedingTime: "Seeding time goal"
    case .inactiveTime: "Inactive goal"
    }
  }
}

/// How a limit is shown as text and read back (the same formats as the
/// Settings pages, so a number is written one way everywhere).
struct LimitFormats: Equatable, Sendable {
  let locale: Locale

  var speed: SettingsFormat<Int> { .megabytesPerSecond(locale: locale) }
  var ratio: SettingsFormat<Double?> { .optionalDecimal(locale: locale) }
  var seedingTime: SettingsFormat<Int?> { .optionalHoursAsMinutes(locale: locale) }
  var inactiveTime: SettingsFormat<Int?> { .optionalWholeNumber }
}

/// What a limit box holds when the sheet is being filled in.
public struct LimitEntry: Equatable, Sendable {
  public enum Mode: Equatable, Sendable {
    /// What is typed (empty: see `LimitsDraft.several`).
    case own
    /// Take the limit away, so the category's or global setting applies.
    case useDefault
    /// A seed goal only: no goal at all.
    case noGoal
  }

  public var mode = Mode.own
  public var text = ""
  /// False until the person changes it. An untouched field is never sent,
  /// so a value that was only shown (and rounded for showing) can't be
  /// changed by pressing Save.
  public var touched = false

  public init(mode: Mode = .own, text: String = "", touched: Bool = false) {
    self.mode = mode
    self.text = text
    self.touched = touched
  }
}

/// The limits being edited in a sheet: five boxes, what each holds, and
/// whether the person has changed it. Pure values, so what gets sent is
/// tested without a window.
///
/// With one torrent (or a category) the boxes start with the stored
/// values, and an empty box means "none of its own". With several
/// torrents the boxes start empty and an empty box means "leave as it
/// is" (Umbra changes only the fields it is sent); clearing a limit on
/// all of them is a separate choice in the box's menu.
public struct LimitsDraft: Equatable, Sendable {
  /// A choice in a box's menu.
  public enum Choice: Equatable, Sendable {
    /// Leave as it is (several torrents only).
    case leave
    /// Use the category's or global setting.
    case useDefault
    /// No goal at all (seed goals only).
    case noGoal
  }

  public let several: Bool
  public private(set) var entries: [LimitField: LimitEntry]
  /// How each box started, which "Leave as it is" goes back to.
  private let initial: [LimitField: LimitEntry]
  let formats: LimitFormats

  public subscript(field: LimitField) -> LimitEntry { entries[field] ?? LimitEntry() }

  /// All boxes empty and untouched. `several`: the draft is for more than
  /// one torrent.
  public init(several: Bool = false, locale: Locale = .current) {
    self.init(
      several: several,
      initial: Dictionary(uniqueKeysWithValues: LimitField.allCases.map { ($0, LimitEntry()) }),
      locale: locale)
  }

  private init(several: Bool, initial: [LimitField: LimitEntry], locale: Locale) {
    self.several = several
    self.initial = initial
    entries = initial
    formats = LimitFormats(locale: locale)
  }

  /// The stored values of one torrent.
  public init(own: Components.Schemas.OwnLimits, locale: Locale = .current) {
    let f = LimitFormats(locale: locale)
    self.init(
      several: false,
      initial: [
        .downloadLimit: LimitEntry(text: f.speed.text(own.downloadLimitKBs)),
        .uploadLimit: LimitEntry(text: f.speed.text(own.uploadLimitKBs)),
        .ratio: Self.goal(own.ratio.map { $0 < 0 } ?? false, text: f.ratio.text(own.ratio)),
        .seedingTime: Self.goal(
          own.seedingMinutes.map { $0 < 0 } ?? false, text: f.seedingTime.text(own.seedingMinutes)),
        .inactiveTime: Self.goal(
          own.inactiveMinutes.map { $0 < 0 } ?? false,
          text: f.inactiveTime.text(own.inactiveMinutes)),
      ], locale: locale)
  }

  /// The stored values of a category.
  public init(category: CategoryLimits, locale: Locale = .current) {
    let f = LimitFormats(locale: locale)
    self.init(
      several: false,
      initial: [
        .downloadLimit: LimitEntry(text: f.speed.text(category.downloadLimitKBs ?? 0)),
        .uploadLimit: LimitEntry(text: f.speed.text(category.uploadLimitKBs ?? 0)),
        .ratio: Self.goal(
          category.ratio.map { $0 < 0 } ?? false, text: f.ratio.text(category.ratio)),
        .seedingTime: Self.goal(
          category.seedingMinutes.map { $0 < 0 } ?? false,
          text: f.seedingTime.text(category.seedingMinutes)),
        .inactiveTime: Self.goal(
          category.inactiveMinutes.map { $0 < 0 } ?? false,
          text: f.inactiveTime.text(category.inactiveMinutes)),
      ], locale: locale)
  }

  private static func goal(_ none: Bool, text: String) -> LimitEntry {
    none ? LimitEntry(mode: .noGoal) : LimitEntry(text: text)
  }

  // MARK: Editing

  /// Typing in a box.
  public mutating func type(_ text: String, into field: LimitField) {
    entries[field] = LimitEntry(mode: .own, text: text, touched: true)
  }

  /// Choosing from a box's menu.
  public mutating func choose(_ choice: Choice, for field: LimitField) {
    switch choice {
    case .leave: entries[field] = initial[field] ?? LimitEntry()
    case .useDefault: entries[field] = LimitEntry(mode: .useDefault, touched: true)
    case .noGoal: entries[field] = LimitEntry(mode: .noGoal, touched: true)
    }
  }

  /// Whether the person has changed anything.
  public var isEdited: Bool { entries.values.contains { $0.touched } }

  // MARK: Reading what was typed

  /// What the box holds as a change, or nil when it is left alone.
  /// `.unreadable` when what was typed isn't a number.
  private enum Reading<Value: Equatable & Sendable> {
    case change(LimitChange<Value>)
    case unreadable
  }

  /// Whether this box is left as it is.
  private func isLeftAlone(_ field: LimitField) -> Bool {
    let entry = self[field]
    if !entry.touched { return true }
    // Several torrents: an emptied box is the same as an untouched one.
    return several && entry.mode == .own && entry.text.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private func speed(_ field: LimitField) -> Reading<Int> {
    let entry = self[field]
    if isLeftAlone(field) { return .change(.keep) }
    if entry.mode != .own { return .change(.useDefault) }
    switch formats.speed.read(entry.text) {
    case .unreadable: return .unreadable
    // 0 is "none of its own", which is what an empty box means too.
    case .value(let kbs): return .change(kbs == 0 ? .useDefault : .set(kbs))
    }
  }

  private func goal<Value: Equatable & Sendable>(
    _ field: LimitField, read: (String) -> SettingsFormat<Value?>.Reading
  ) -> Reading<Value> {
    let entry = self[field]
    if isLeftAlone(field) { return .change(.keep) }
    switch entry.mode {
    case .useDefault: return .change(.useDefault)
    case .noGoal: return .change(.noGoal)
    case .own:
      switch read(entry.text) {
      case .unreadable: return .unreadable
      case .value(let value): return .change(value.map { .set($0) } ?? .useDefault)
      }
    }
  }

  /// Whether the box holds something that isn't a number.
  private func isUnreadable(_ field: LimitField) -> Bool {
    switch field {
    case .downloadLimit, .uploadLimit:
      if case .unreadable = speed(field) { return true }
    case .ratio:
      if case .unreadable = goal(field, read: formats.ratio.read) { return true }
    case .seedingTime:
      if case .unreadable = goal(field, read: formats.seedingTime.read) { return true }
    case .inactiveTime:
      if case .unreadable = goal(field, read: formats.inactiveTime.read) { return true }
    }
    return false
  }

  /// The fields whose text isn't a number, with the words to show under them.
  public var problems: [LimitField: String] {
    var result: [LimitField: String] = [:]
    for field in LimitField.allCases where isUnreadable(field) { result[field] = "Enter a number." }
    return result
  }

  // MARK: What to send

  /// The changes to some torrents' own limits, or nil while a box holds
  /// something that isn't a number (nothing half-typed is ever sent).
  public func torrentChanges() -> TorrentLimitChanges? {
    guard problems.isEmpty else { return nil }
    var changes = TorrentLimitChanges()
    if case .change(let change) = speed(.downloadLimit) { changes.downloadLimitKBs = change }
    if case .change(let change) = speed(.uploadLimit) { changes.uploadLimitKBs = change }
    if case .change(let change) = goal(.ratio, read: formats.ratio.read) { changes.ratio = change }
    if case .change(let change) = goal(.seedingTime, read: formats.seedingTime.read) {
      changes.seedingMinutes = change
    }
    if case .change(let change) = goal(.inactiveTime, read: formats.inactiveTime.read) {
      changes.inactiveMinutes = change
    }
    return changes
  }

  /// A category's limits with the changes made here, or nil while a box
  /// holds something that isn't a number. A category is saved whole, so
  /// the fields left alone keep what `base` had. An empty box is none of
  /// its own: a goal then follows Settings → Seeding (left out), a speed
  /// is 0.
  public func categoryLimits(base: CategoryLimits) -> CategoryLimits? {
    guard problems.isEmpty, let changes = torrentChanges() else { return nil }
    var result = base
    func speed(_ change: LimitChange<Int>, _ old: Int?) -> Int? {
      switch change {
      case .keep: old
      case .useDefault, .noGoal: nil
      case .set(let kbs): kbs
      }
    }
    func goal<V>(_ change: LimitChange<V>, _ old: V?, none: V) -> V? {
      switch change {
      case .keep: old
      case .useDefault: nil
      case .noGoal: none
      case .set(let value): value
      }
    }
    result.downloadLimitKBs = speed(changes.downloadLimitKBs, base.downloadLimitKBs)
    result.uploadLimitKBs = speed(changes.uploadLimitKBs, base.uploadLimitKBs)
    result.ratio = goal(changes.ratio, base.ratio, none: -1)
    result.seedingMinutes = goal(changes.seedingMinutes, base.seedingMinutes, none: -1)
    result.inactiveMinutes = goal(changes.inactiveMinutes, base.inactiveMinutes, none: -1)
    return result
  }
}

/// A category's own limits and goals, as Umbra stores them (see the
/// Category schema): a speed of 0 or none is no limit of its own; a goal
/// left out follows Settings → Seeding and a negative one is no goal.
public struct CategoryLimits: Equatable, Sendable {
  public var ratio: Double?
  public var seedingMinutes: Int?
  public var inactiveMinutes: Int?
  public var downloadLimitKBs: Int?
  public var uploadLimitKBs: Int?

  public init(
    ratio: Double? = nil, seedingMinutes: Int? = nil, inactiveMinutes: Int? = nil,
    downloadLimitKBs: Int? = nil, uploadLimitKBs: Int? = nil
  ) {
    self.ratio = ratio
    self.seedingMinutes = seedingMinutes
    self.inactiveMinutes = inactiveMinutes
    self.downloadLimitKBs = downloadLimitKBs
    self.uploadLimitKBs = uploadLimitKBs
  }

  public init(_ category: Components.Schemas.Category) {
    self.init(
      ratio: category.ratio, seedingMinutes: category.seedingMinutes,
      inactiveMinutes: category.inactiveMinutes, downloadLimitKBs: category.downloadLimitKBs,
      uploadLimitKBs: category.uploadLimitKBs)
  }

  func apply(to category: inout Components.Schemas.Category) {
    category.ratio = ratio
    category.seedingMinutes = seedingMinutes
    category.inactiveMinutes = inactiveMinutes
    category.downloadLimitKBs = downloadLimitKBs
    category.uploadLimitKBs = uploadLimitKBs
  }
}
