import Foundation
import Observation

/// The two kinds of thing Umbra can open from outside.
public enum OpeningKind: CaseIterable, Sendable {
  case torrentFiles
  case magnetLinks
}

/// The app macOS uses for one kind, as far as this page needs to know.
public struct DefaultAppReading: Equatable, Sendable {
  /// The app's name, as the person knows it.
  public let name: String
  /// It is Umbra.
  public let isUmbra: Bool

  public init(name: String, isUmbra: Bool) {
    self.name = name
    self.isUmbra = isUmbra
  }
}

/// Reads and changes which app macOS opens things with. The real one (in
/// the app) asks macOS; tests and pictures use a fake that never does.
@MainActor
public protocol DefaultAppService {
  /// The app that opens this kind now; nil if there is none.
  func current(for kind: OpeningKind) -> DefaultAppReading?
  /// Makes Umbra the app that opens this kind. macOS may ask the person
  /// to confirm, and may refuse.
  func makeDefault(for kind: OpeningKind) async throws
}

/// Settings → General → "Opening torrents": for torrent files and magnet
/// links, whether Umbra opens them, and the button that makes it so.
@MainActor @Observable
public final class DefaultAppModel {
  private let service: any DefaultAppService
  private var readings: [OpeningKind: DefaultAppReading] = [:]
  private var problems: [OpeningKind: String]
  /// Kinds whose change is on its way (the button waits).
  private var working: Set<OpeningKind> = []

  /// `problems` is only for pictures of a failure.
  public init(service: any DefaultAppService, problems: [OpeningKind: String] = [:]) {
    self.service = service
    self.problems = problems
    refresh()
  }

  /// Reads macOS again (the page opened, or the app came to the front).
  public func refresh() {
    for kind in OpeningKind.allCases {
      readings[kind] = service.current(for: kind)
    }
  }

  /// "Umbra is the default", "Opens in qBittorrent" or "No default app".
  public func status(for kind: OpeningKind) -> String {
    guard let reading = readings[kind] else { return "No default app" }
    return reading.isUmbra ? "Umbra is the default" : "Opens in \(reading.name)"
  }

  public func isUmbra(_ kind: OpeningKind) -> Bool { readings[kind]?.isUmbra == true }

  /// The button works unless Umbra already is the default, or a change is
  /// on its way.
  public func canMakeDefault(_ kind: OpeningKind) -> Bool {
    !isUmbra(kind) && !working.contains(kind)
  }

  /// What went wrong the last time, in plain words; nil when nothing did.
  public func problem(for kind: OpeningKind) -> String? { problems[kind] }

  /// Asks macOS to make Umbra the default, once, then reads what it says.
  public func makeDefault(_ kind: OpeningKind) async {
    guard canMakeDefault(kind) else { return }
    working.insert(kind)
    problems[kind] = nil
    defer { working.remove(kind) }
    do {
      try await service.makeDefault(for: kind)
    } catch {
      problems[kind] = "macOS wouldn't change it. \(error.localizedDescription)"
      refresh()
      return
    }
    refresh()
    if !isUmbra(kind) {
      problems[kind] = "macOS didn't change it. If it asked you to confirm, choose Use Umbra."
    }
  }
}
