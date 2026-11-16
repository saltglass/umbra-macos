import Foundation
import UmbraAPI

/// What applies when a limit box is empty, for the box's grey hint text:
/// the category's own setting if it has one, otherwise the global seed goal.
/// What is not known (Umbra hasn't answered, or the torrents are in
/// different categories) is said in general words, never guessed.
public struct LimitHints: Equatable, Sendable {
  /// The global seed goals (Settings → Seeding); nil until known.
  public var global: Components.Schemas.SeedingSettings?
  /// The category the torrent is in; nil for none.
  public var category: Components.Schemas.Category?
  /// The torrents are in different categories: nothing to name.
  public var mixedCategories = false
  /// What the sheet is for: a category's own sheet has no category above it.
  public var forCategory = false
  let formats: LimitFormats

  public init(
    global: Components.Schemas.SeedingSettings? = nil,
    category: Components.Schemas.Category? = nil, mixedCategories: Bool = false,
    forCategory: Bool = false, locale: Locale = .current
  ) {
    self.global = global
    self.category = category
    self.mixedCategories = mixedCategories
    self.forCategory = forCategory
    formats = LimitFormats(locale: locale)
  }

  public static func == (a: Self, b: Self) -> Bool {
    a.global == b.global && a.category == b.category && a.mixedCategories == b.mixedCategories
      && a.forCategory == b.forCategory
  }

  /// The hint for an empty box, or for a box in a special state.
  public func placeholder(for field: LimitField, in draft: LimitsDraft) -> String {
    let entry = draft[field]
    if entry.mode == .noGoal { return forCategory ? "No goal" : "None for this torrent" }
    if draft.several && entry.mode == .own && !entry.touched { return "Leave as it is" }
    return applying(field)
  }

  /// What applies to a torrent (or category) with nothing of its own in `field`.
  func applying(_ field: LimitField) -> String {
    if field.isGoal { return goalText(field) }
    if forCategory { return "No limit" }
    if mixedCategories { return "Category's limit, if any" }
    let kbs = field == .downloadLimit ? category?.downloadLimitKBs : category?.uploadLimitKBs
    if let kbs, kbs > 0 { return "Category: \(formats.speed.text(kbs)) MB/s" }
    return "No limit"
  }

  private func goalText(_ field: LimitField) -> String {
    func describe(_ value: String?, none: Bool, from: String) -> String {
      none ? "No goal" : "\(from): \(value ?? "")"
    }
    // The category's goal first (a torrent, not a category), then the global one.
    if !forCategory {
      if mixedCategories { return "Category's or global goal" }
      if let category {
        switch field {
        case .ratio:
          if let v = category.ratio {
            return describe(formats.ratio.text(v), none: v < 0, from: "Category")
          }
        case .seedingTime:
          if let v = category.seedingMinutes {
            return describe(
              formats.seedingTime.text(v) + " hours", none: v < 0, from: "Category")
          }
        default:
          if let v = category.inactiveMinutes {
            return describe(
              formats.inactiveTime.text(v) + " min", none: v < 0, from: "Category")
          }
        }
      }
    }
    guard let global else { return forCategory ? "Global goal" : "Category's or global goal" }
    switch field {
    case .ratio:
      return global.ratio.map { "Global: \(formats.ratio.text($0))" } ?? "No goal"
    case .seedingTime:
      return global.seedingMinutes.map { "Global: \(formats.seedingTime.text($0)) hours" }
        ?? "No goal"
    default:
      return global.inactiveMinutes.map { "Global: \(formats.inactiveTime.text($0)) min" }
        ?? "No goal"
    }
  }
}
