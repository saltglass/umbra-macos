import AppKit
import UmbraKit

/// The real `DefaultAppService`: asks macOS which app opens torrent files
/// and magnet links, and asks it to make Umbra that app. Pictures of the
/// views never use this one (see `FakeDefaultApps`).
@MainActor
struct WorkspaceDefaultApps: DefaultAppService {
  /// Any magnet address will do: macOS only looks at the part before the colon.
  private static let magnetSample = URL(string: "magnet:")!

  func current(for kind: OpeningKind) -> DefaultAppReading? {
    let workspace = NSWorkspace.shared
    let app: URL? =
      switch kind {
      case .torrentFiles: workspace.urlForApplication(toOpen: AddTorrentPresenter.torrentType)
      case .magnetLinks: workspace.urlForApplication(toOpen: Self.magnetSample)
      }
    guard let app else { return nil }
    // Compared by bundle ID, so a Debug build and a Release build count as the same app.
    let isUmbra =
      Bundle(url: app)?.bundleIdentifier != nil
      && Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier
    let name = FileManager.default.displayName(atPath: app.path)
    return DefaultAppReading(name: name, isUmbra: isUmbra)
  }

  func makeDefault(for kind: OpeningKind) async throws {
    let workspace = NSWorkspace.shared
    let umbra = Bundle.main.bundleURL
    switch kind {
    case .torrentFiles:
      try await workspace.setDefaultApplication(at: umbra, toOpen: AddTorrentPresenter.torrentType)
    case .magnetLinks:
      try await workspace.setDefaultApplication(at: umbra, toOpenURLsWithScheme: "magnet")
    }
  }
}
