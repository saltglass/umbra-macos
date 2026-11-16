import SwiftUI
import UmbraKit

/// The line under the list, as on the web page: free space, whether peers
/// can connect in (and on which port), DHT nodes, and the total speeds
/// (hover them for this session's totals). "Reconnecting…" is not here: it
/// shows as a quiet note over the list (`StatusBanners`).
struct StatusBarView: View {
  let info: StatusBarInfo

  var body: some View {
    // On a narrow window the less important parts give way first.
    ViewThatFits(in: .horizontal) {
      line(full: true)
      line(full: false)
    }
    .font(.subheadline)
    .foregroundStyle(.secondary)
    .monospacedDigit()
    .lineLimit(1)
    .padding(.horizontal, 12)
    .frame(height: 26)
  }

  private func line(full: Bool) -> some View {
    HStack(spacing: 16) {
      if full, let free = info.freeSpace {
        Label(free, systemImage: "internaldrive")
      }
      Label {
        Text(info.port.map { "\(info.incoming) · \($0)" } ?? info.incoming)
      } icon: {
        Image(systemName: info.incomingWorks ? "circle.fill" : "circle")
          .imageScale(.small)
          .foregroundStyle(info.incomingWorks ? ColorRole.green.color : ColorRole.secondary.color)
      }
      if full {
        Label(info.dht, systemImage: "network")
      }
      Spacer(minLength: 16)
      HStack(spacing: 10) {
        Label(info.down, systemImage: "arrow.down")
        Label(info.up, systemImage: "arrow.up")
      }
      .help(info.session)
    }
  }
}
