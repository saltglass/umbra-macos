import Foundation
import UmbraAPI

/// One update from Umbra's live feed, read into Swift types.
///
/// The kinds and their shapes come from `GET /events` in `openapi.yaml` and
/// from Umbra's `internal/events/events.go` (the event names) and
/// `internal/api/feed.go` (what is sent when).
public enum FeedEvent: Sendable, Equatable {
  /// `torrents.snapshot`: every torrent. Sent first on every connection.
  case snapshot(Components.Schemas.TorrentsSnapshot)
  /// `torrents.delta`: the torrents added, changed or removed since revision `from`.
  case delta(Components.Schemas.TorrentsDelta)
  /// `transfer`: totals for the status bar, including the VPN state. About once a second.
  case transfer(Components.Schemas.Transfer)
  /// `creations`: the torrents being made with "Create torrent".
  case creations([Components.Schemas.Creation])
  /// `torrent.finished`: a download just finished (for a notification).
  case finished(Components.Schemas.TorrentFinished)
  /// `settings.changed`: a settings group changed somewhere; fetch it again.
  case settingsChanged(group: String)

  /// The `event:` names Umbra uses.
  enum Name {
    static let snapshot = "torrents.snapshot"
    static let delta = "torrents.delta"
    static let transfer = "transfer"
    static let creations = "creations"
    static let finished = "torrent.finished"
    static let settingsChanged = "settings.changed"
  }

  /// Reads a stream message. Returns nil for a kind this app doesn't know
  /// (the web app ignores those too, so a newer Umbra can add kinds safely);
  /// throws if a known kind's JSON doesn't fit.
  public init?(_ message: ServerSentEvent) throws {
    let data = Data(message.data.utf8)
    let decoder = FeedJSON.decoder
    switch message.type {
    case Name.snapshot:
      self = .snapshot(try decoder.decode(Components.Schemas.TorrentsSnapshot.self, from: data))
    case Name.delta:
      self = .delta(try decoder.decode(Components.Schemas.TorrentsDelta.self, from: data))
    case Name.transfer:
      self = .transfer(try decoder.decode(Components.Schemas.Transfer.self, from: data))
    case Name.creations:
      self = .creations(try decoder.decode([Components.Schemas.Creation].self, from: data))
    case Name.finished:
      self = .finished(try decoder.decode(Components.Schemas.TorrentFinished.self, from: data))
    case Name.settingsChanged:
      self = .settingsChanged(group: try decoder.decode(SettingsChanged.self, from: data).group)
    default:
      return nil
    }
  }
}

/// The `settings.changed` message: `{"group": "security"}`.
///
/// The API description has no named schema for this (it is written out in the
/// text of `GET /events`), so it is mirrored here from the web app's
/// `web/src/hooks/feed.ts`, which reads it as `{ group: string }`.
struct SettingsChanged: Decodable {
  let group: String
}

/// Reads Umbra's JSON.
enum FeedJSON {
  /// Umbra writes times the way Go does: to the nanosecond when there is a
  /// fraction, with none when the time is a whole second. `UmbraDates`
  /// accepts both (the generated client uses the same rules).
  static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let text = try decoder.singleValueContainer().decode(String.self)
      if let date = UmbraDates.parse(text) { return date }
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Not an ISO 8601 time: \(text)")
      )
    }
    return decoder
  }()
}
