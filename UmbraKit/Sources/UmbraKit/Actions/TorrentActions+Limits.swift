import Foundation
import OpenAPIRuntime
import UmbraAPI

/// Moving torrents' files and a torrent's own limits.
extension TorrentActions {
  // MARK: Moving (POST /torrents/move)

  /// Asks Umbra to move the torrents' files to a folder (a full path on
  /// the server). Umbra does it in the background and the list shows
  /// "Moving"; a finished torrent keeps seeding meanwhile. Umbra refuses
  /// a folder that doesn't exist or can't be written to, and a torrent
  /// that can't be moved right now, in its own words.
  public func move(_ hashes: [String], to folder: String) async throws(UmbraError) {
    guard !hashes.isEmpty else { return }
    let output = try await call {
      try await client.moveTorrents(body: .json(.init(hashes: hashes, folder: folder)))
    }
    guard case .noContent = output else { throw .unexpectedAnswer }
  }

  // MARK: A torrent's own limits

  /// A torrent's own limits, the ones in force, and its category.
  public func limits(of hash: String) async throws(UmbraError) -> Components.Schemas.TorrentLimits {
    let output = try await call { try await client.getTorrentLimits(path: .init(hash: hash)) }
    guard case .ok(let ok) = output, case .json(let limits) = ok.body else {
      throw .unexpectedAnswer
    }
    return limits
  }

  /// Changes some of the torrents' own limits; fields marked `.keep`
  /// stay as each torrent has them. Nothing is sent when nothing changes.
  public func setLimits(_ changes: TorrentLimitChanges, for hashes: [String])
    async throws(UmbraError)
  {
    guard !hashes.isEmpty, !changes.isEmpty else { return }
    let body = changes.body(hashes: hashes)
    let result: Result<Operations.setTorrentsLimits.Output, UmbraError> =
      await LimitsBody.$json.withValue(body) {
        do throws(UmbraError) {
          // The body written here is only a stand-in; see LimitsBodyMiddleware.
          return .success(
            try await call {
              try await client.setTorrentsLimits(body: .json(.init(hashes: hashes)))
            })
        } catch {
          return .failure(error)
        }
      }
    let output = try result.get()
    guard case .noContent = output else { throw .unexpectedAnswer }
  }

  // MARK: What applies when a limit is blank

  /// The global seed goals (Settings → Seeding), for the sheet's hints.
  public func seedingGoals() async throws(UmbraError) -> Components.Schemas.SeedingSettings {
    let output = try await call { try await client.getSeedingSettings() }
    guard case .ok(let ok) = output, case .json(let goals) = ok.body else {
      throw .unexpectedAnswer
    }
    return goals
  }

  /// The categories with their own limits (Settings → Downloads).
  public func categories() async throws(UmbraError) -> [Components.Schemas.Category] {
    let output = try await call { try await client.getDownloadsSettings() }
    guard case .ok(let ok) = output, case .json(let settings) = ok.body else {
      throw .unexpectedAnswer
    }
    return settings.categories
  }
}
