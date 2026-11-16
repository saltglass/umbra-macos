import Foundation

/// Which data folder the helper uses, and how it may behave.
///
/// There are three kinds, made only by the factory functions below:
///
/// - **release**: `~/Library/Application Support/Umbra`, the person's real
///   torrents and settings, held until a VPN is chosen (see `holdUntilVpn`).
/// - **development**: `~/Library/Application Support/Umbra-Dev`, always with
///   `UMBRA_LOOPBACK_ONLY=true` so a development build never reaches the
///   internet.
/// - **testing**: any folder a test names (a temporary one), also loopback-only.
///
/// Anything that isn't a release build is refused the release folder (see
/// `checkAllowed`), so a development build or a test can never touch the real
/// data, even by mistake.
public struct HelperEnvironment: Sendable, Equatable {
  public enum Kind: Sendable, Equatable {
    case release, development, testing
  }

  public let kind: Kind
  /// Where Umbra keeps its database, settings, downloads and our helper.log.
  public let dataFolder: URL
  /// Umbra's UMBRA_HOLD_UNTIL_VPN: while no VPN is saved and the person
  /// has never chosen "Start without VPN", every torrent is held and
  /// nothing touches the network (Dan, 2026-11-13). Adding a VPN, or
  /// choosing to start without one, releases it, and Umbra remembers the
  /// choice. Always on for the real app; off for development (which is
  /// loopback-only anyway); a test can turn it on.
  public let holdUntilVpn: Bool

  private init(kind: Kind, dataFolder: URL, holdUntilVpn: Bool) {
    self.kind = kind
    self.dataFolder = dataFolder.standardizedFileURL
    self.holdUntilVpn = holdUntilVpn
  }

  /// Development and tests keep Umbra on 127.0.0.1: no trackers, no peers,
  /// no IP checks. Only a release build talks to the outside world.
  public var loopbackOnly: Bool { kind != .release }

  /// The person's own Application Support folder.
  public static var userApplicationSupport: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
  }

  /// The release data folder under `applicationSupport`.
  public static func releaseFolder(applicationSupport: URL = userApplicationSupport) -> URL {
    applicationSupport.appending(path: "Umbra", directoryHint: .isDirectory)
  }

  /// The real app's environment.
  public static func release(applicationSupport: URL = userApplicationSupport) -> Self {
    Self(
      kind: .release, dataFolder: releaseFolder(applicationSupport: applicationSupport),
      holdUntilVpn: true)
  }

  /// A development build's environment: its own folder, loopback only.
  public static func development(applicationSupport: URL = userApplicationSupport) -> Self {
    Self(
      kind: .development,
      dataFolder: applicationSupport.appending(path: "Umbra-Dev", directoryHint: .isDirectory),
      holdUntilVpn: false)
  }

  /// A test's environment: the folder it names, loopback only. With
  /// `holdUntilVpn`, it starts held as the real app does.
  public static func testing(dataFolder: URL, holdUntilVpn: Bool = false) -> Self {
    Self(kind: .testing, dataFolder: dataFolder, holdUntilVpn: holdUntilVpn)
  }

  /// Throws if this environment may not use its data folder: anything but a
  /// release build pointed at the release folder, inside it, or at a folder
  /// containing it. Checked before every start of the helper.
  public func checkAllowed() throws(HelperError) {
    guard kind != .release else { return }
    let mine = Self.resolved(dataFolder)
    // The real one always, whatever folder this environment was built from.
    let release = Self.resolved(Self.releaseFolder())
    if mine == release || mine.starts(with: release) || release.starts(with: mine) {
      throw HelperError(
        message:
          "This development build refused to use the real Umbra data folder (\(release.joined(separator: "/"))). "
          + "Development builds and tests must use their own folder.",
        logTail: [])
    }
  }

  /// The folder as path components, symbolic links followed, so two
  /// spellings of the same folder compare equal.
  ///
  /// Foundation's own `resolvingSymlinksInPath` gives up on a link to a
  /// folder that doesn't exist yet (such as the release folder before the
  /// app has ever run), so the links are followed here one part at a time.
  static func resolved(_ url: URL) -> [String] {
    var parts: [String] = []
    var pending = Array(url.standardizedFileURL.pathComponents.reversed())
    var linksFollowed = 0
    while let part = pending.popLast() {
      switch part {
      case "/": parts = ["/"]
      case ".": continue
      case "..": if parts.count > 1 { parts.removeLast() }
      default:
        parts.append(part)
        let path = NSString.path(withComponents: parts)
        // A link loop can't make this run forever.
        guard linksFollowed < 64,
          let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path)
        else { continue }
        linksFollowed += 1
        parts.removeLast()
        // Put the link's target in its place, then carry on with the rest.
        // (An absolute target starts with "/", which starts again from the top.)
        pending.append(contentsOf: (target as NSString).pathComponents.reversed())
      }
    }
    return parts
  }

  /// The address file the helper writes once it is listening.
  var addressFile: URL {
    dataFolder.appending(path: "helper-address", directoryHint: .notDirectory)
  }
  /// Where the helper's output goes.
  var logFile: URL { dataFolder.appending(path: "helper.log", directoryHint: .notDirectory) }

  /// The environment variables the helper is started with.
  ///
  /// It starts from the app's own (so things like `PATH`, `HOME` and the
  /// time zone carry over) but drops every `UMBRA_` variable first: nothing
  /// set for the app (such as a development attach key) may leak into the
  /// helper or change how it runs.
  func processEnvironment(token: String, inherited: [String: String]) -> [String: String] {
    var env = inherited.filter { !$0.key.hasPrefix("UMBRA_") }
    env["UMBRA_DATA_DIR"] = dataFolder.path(percentEncoded: false)
    env["UMBRA_LISTEN"] = "127.0.0.1:0"  // any free port, loopback only
    env["UMBRA_ADDR_FILE"] = addressFile.path(percentEncoded: false)
    env["UMBRA_LAUNCH_TOKEN"] = token
    env["UMBRA_EXIT_WITH_PARENT"] = "true"
    // File → Create Torrent… lets the person pick a file or folder anywhere
    // on this Mac. Umbra allows that only to the launch token's holder
    // (this app), and never for its own data folder (Dan, 2026-11-14).
    env["UMBRA_SHARE_ANYWHERE"] = "true"
    if loopbackOnly { env["UMBRA_LOOPBACK_ONLY"] = "true" }
    if holdUntilVpn { env["UMBRA_HOLD_UNTIL_VPN"] = "true" }
    return env
  }
}
