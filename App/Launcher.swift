import Foundation

/// Where the program starts. Normally it just opens the app; in Debug
/// builds, `--snapshot <folder>` instead draws pictures of the views into
/// that folder and quits, without a window or a helper (see SnapshotRunner).
@main
@MainActor
enum Launcher {
  static func main() {
    #if DEBUG
      let arguments = CommandLine.arguments
      if let flag = arguments.firstIndex(of: "--snapshot") {
        let folder = flag + 1 < arguments.count ? arguments[flag + 1] : "build/snapshots"
        SnapshotRunner.run(into: URL(filePath: folder, directoryHint: .isDirectory))
      }
    #endif
    UmbraApp.main()
  }
}
