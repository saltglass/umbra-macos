import Foundation
import UmbraAPI

/// Where Umbra saves a new torrent, as Settings → Downloads says: in its
/// category's folder when that category has one, otherwise in the default
/// folder. The Add sheet shows it read-only, as the web page does (Umbra's
/// add call can take another folder, but the web page doesn't offer one,
/// so neither does the sheet).
public struct SaveFolders: Equatable, Sendable {
  /// The folder used without a category (never empty once Umbra has said).
  public let defaultFolder: String
  /// The categories set up in Settings, in Umbra's order.
  public let categoryNames: [String]
  /// Each category's own folder; categories without one aren't listed.
  public let categoryFolders: [String: String]

  public init(
    defaultFolder: String, categoryNames: [String] = [], categoryFolders: [String: String] = [:]
  ) {
    self.defaultFolder = defaultFolder
    self.categoryNames = categoryNames
    self.categoryFolders = categoryFolders.filter { !$0.value.isEmpty }
  }

  init(_ settings: Components.Schemas.DownloadsSettings) {
    // An empty `folder` means Umbra's own default, which it reports apart.
    defaultFolder = settings.folder.isEmpty ? (settings.defaultFolder ?? "") : settings.folder
    categoryNames = settings.categories.map(\.name)
    var folders: [String: String] = [:]
    for category in settings.categories where !category.folder.isEmpty {
      folders[category.name] = category.folder
    }
    categoryFolders = folders
  }

  /// The folder a torrent in `category` ("" for none) is saved in; nil
  /// when Umbra hasn't said.
  public func folder(for category: String) -> String? {
    let folder = categoryFolders[category] ?? defaultFolder
    return folder.isEmpty ? nil : folder
  }
}
