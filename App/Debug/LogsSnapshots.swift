#if DEBUG
  import SwiftUI
  import UmbraKit

  /// Pictures of the Logs window: a mix of levels, filtered to warnings,
  /// searching, reconnecting, and not connected. All lines are made up
  /// (addresses are from the documentation range 198.51.100.x).
  @MainActor
  enum LogsSnapshots {
    private static let size = CGSize(width: 820, height: 480)

    static var entries: [SnapshotEntry] {
      [
        entry("logs", model: { model() }),
        entry(
          "logs-warnings",
          model: {
            let m = model()
            m.levelFilter = .warningsAndErrors
            return m
          }),
        entry(
          "logs-search",
          model: {
            let m = model()
            m.searchText = "198.51.100"
            return m
          }),
        entry("logs-reconnecting", model: { model(phase: .reconnecting) }),
        entry("logs-not-connected", model: { LogsModel.fixture(lines: [], phase: .notConnected) }),
      ]
    }

    private static func entry(_ name: String, model: @escaping @MainActor () -> LogsModel)
      -> SnapshotEntry
    {
      SnapshotEntry(name: name, size: size, windowFrame: true) {
        AnyView(LogsView(model: model(), tableAutosaveName: nil))
      }
    }

    private static func model(phase: LogsModel.Phase = .live) -> LogsModel {
      LogsModel.fixture(lines: sample, phase: phase)
    }

    private static let sample: [LogLine] = {
      let rows: [(LogLevel, String, String)] = [
        (.info, "Umbra", "Umbra 1.8.0 started"),
        (.info, "Umbra", "Listening for peers on port 6881"),
        (.info, "Umbra", "VPN connected  address=198.51.100.7"),
        (.info, "Example Linux ISO", "Added  size=4.2 GB"),
        (
          .info, "Example Linux ISO",
          "Tracker answered  peers=48 url=https://tracker.example.org/announce"
        ),
        (
          .warning, "Example Linux ISO",
          "Tracker is slow to answer  url=https://tracker.example.org/announce"
        ),
        (.info, "Sample Documentary", "Added  size=1.7 GB"),
        (.info, "Umbra", "Peer connected  address=198.51.100.23"),
        (
          .warning, "Sample Documentary",
          "Peer 198.51.100.41 sent a piece that didn't match; ignoring it"
        ),
        (.info, "Example Linux ISO", "Finished downloading"),
        (
          .error, "Sample Documentary",
          "Couldn't write to the download folder: no space left on the disk"
        ),
        (.info, "Umbra", "Saved 2 torrents"),
        (.warning, "Umbra", "The VPN dropped; downloads are held until it is back"),
        (.info, "Umbra", "VPN connected  address=198.51.100.9"),
        (.info, "Sample Documentary", "Resumed"),
        (.error, "Umbra", "Couldn't reach the time server: timed out after 10 s"),
        (.info, "Sample Documentary", "Peer connected  address=198.51.100.88"),
      ]
      return rows.enumerated().map { index, row in
        LogLine(
          id: Int64(index + 1), time: Fixtures.now.addingTimeInterval(Double(index) * 7.5),
          level: row.0, source: row.1, text: row.2)
      }
    }()
  }
#endif
