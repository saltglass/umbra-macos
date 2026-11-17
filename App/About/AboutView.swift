import AppKit
import SwiftUI
import UmbraKit

/// Where "Source Code" goes.
let sourceCodeAddress = URL(string: "https://github.com/saltglass/umbra-macos")!

/// The About Umbra window's contents, in the usual Mac style: the icon, the
/// name, the versions, a line about what it is, and two buttons. This view
/// only draws what it is given; `AboutWindow` supplies the real values.
struct AboutView: View {
  let info: AboutInfo
  /// "Umbra server 0.4.0", or "Umbra server: not running" (see `AboutInfo`).
  let serverLine: String
  let onSourceCode: () -> Void
  let onLicences: () -> Void

  var body: some View {
    VStack(spacing: 4) {
      // Asked of macOS by the app's place on disk: NSApp.applicationIconImage
      // can hand back a blank placeholder when the app is run by its program
      // file rather than opened (as `just snapshot` does).
      Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
        .resizable()
        .frame(width: 112, height: 112)
        .accessibilityHidden(true)
      Text(info.name)
        .font(.title2.bold())
        .padding(.top, 4)
      Text(info.versionLine)
        .foregroundStyle(.secondary)
      Text(serverLine)
        .foregroundStyle(.secondary)

      Text("A BitTorrent client that keeps torrents inside its own VPN.")
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 14)
      Text("Free software under the GNU General Public License, version 3.")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 2)

      HStack(spacing: 10) {
        Button("Source Code", action: onSourceCode)
        Button("Licences…", action: onLicences)
      }
      .padding(.top, 16)
    }
    .font(.callout)
    .padding(.horizontal, 24)
    .padding(.vertical, 24)
    .frame(width: 400)
  }
}

/// The real About window (Umbra → About Umbra): the app's own name and
/// versions, and the server's version once it has answered.
struct AboutWindow: View {
  let session: AppSession
  @Environment(\.openWindow) private var openWindow
  @Environment(\.openURL) private var openURL

  var body: some View {
    AboutView(
      info: AboutInfo(infoDictionary: Bundle.main.infoDictionary),
      serverLine: AboutInfo.serverLine(phase: session.phase, version: session.serverVersion),
      onSourceCode: { openURL(sourceCodeAddress) },
      onLicences: { openWindow(id: "licences") }
    )
    // The window grows to fit its contents and can't be resized.
    .fixedSize()
  }
}
