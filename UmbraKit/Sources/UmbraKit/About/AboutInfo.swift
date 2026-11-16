import Foundation

/// What the About Umbra window says about the app and the server inside it:
/// the app's name and version (read from the app's own Info.plist) and the
/// wording of the "Umbra server" line. The window only draws these words.
public struct AboutInfo: Equatable, Sendable {
  /// "Umbra", or "Umbra Dev" in the development build.
  public let name: String
  /// The app's version, for example "0.1.1"; nil if the app doesn't say.
  public let version: String?
  /// The app's build number, for example "7"; nil if the app doesn't say.
  public let build: String?

  public init(name: String, version: String?, build: String?) {
    self.name = name
    self.version = version
    self.build = build
  }

  /// Reads the app's Info.plist (`Bundle.main.infoDictionary`). The display
  /// name is used, as the Dock does; "Umbra" if there isn't one.
  public init(infoDictionary: [String: Any]?) {
    func text(_ key: String) -> String? {
      guard let value = infoDictionary?[key] as? String, !value.isEmpty else { return nil }
      return value
    }
    self.init(
      name: text("CFBundleDisplayName") ?? text("CFBundleName") ?? "Umbra",
      version: text("CFBundleShortVersionString"), build: text("CFBundleVersion"))
  }

  /// "Version 0.1.1 (7)".
  public var versionLine: String {
    switch (version, build) {
    case (let version?, let build?): "Version \(version) (\(build))"
    case (let version?, nil): "Version \(version)"
    case (nil, _): "Version unknown"
    }
  }

  /// The line about the Umbra server inside the app: its version once it
  /// has answered, otherwise a plain "not running" (it is still starting,
  /// has stopped, or failed to start: the window shows no error and no
  /// spinner, since the main window already says what is wrong).
  ///
  /// `version` is what Umbra reported (its "Version and uptime"); it is
  /// only believed while the server is running, since a restarting server
  /// may come back as a different version.
  public static func serverLine(phase: AppSession.Phase, version: String?) -> String {
    guard phase == .running, let version = tidy(version) else {
      return "Umbra server: not running"
    }
    return "Umbra server \(version)"
  }

  /// Umbra's version as people write it: no spaces round it and no leading
  /// "v" ("v0.4.0" becomes "0.4.0"). Nil if there is nothing left.
  static func tidy(_ version: String?) -> String? {
    guard var text = version?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
    if text.count > 1, text.first == "v", text.dropFirst().first?.isNumber == true {
      text.removeFirst()
    }
    return text.isEmpty ? nil : text
  }
}
