import SwiftUI
import UmbraKit

/// Peers: who the torrent is connected to, busiest first, and how much of
/// the torrent each has.
struct PeersTab: View {
  let model: InspectorModel
  let row: TorrentRow

  var body: some View {
    let fetch = model.peers
    VStack(spacing: 0) {
      if let failure = fetch.failure, fetch.value != nil {
        InspectorNotice(text: failure)
          .padding(8)
      }
      if let peers = fetch.value {
        if peers.isEmpty {
          ContentUnavailableView(
            "No Peers", systemImage: "person.2.slash",
            description: Text(PeerRow.emptyText(for: row.kind)))
        } else {
          Text(peers.count == 1 ? "1 peer connected" : "\(peers.count) peers connected")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
          List(peers) { PeerRowView(peer: $0) }
            .listStyle(.inset)
        }
      } else {
        InspectorFetchState(isLoading: fetch.isLoading, failure: fetch.failure, what: "peers")
      }
    }
  }
}

private struct PeerRowView: View {
  let peer: PeerRow

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 4) {
        Image(systemName: peer.encryptionSymbol)
          .imageScale(.small)
          .foregroundStyle(peer.encryptionRole.color)
          .help(
            peer.isEncrypted ? "Connection is encrypted" : "Connection is not encrypted")
        Text(peer.address)
          .font(.system(.caption, design: .monospaced))
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer(minLength: 4)
        Text("↓ \(peer.downText)")
          .font(.caption)
          .monospacedDigit()
      }
      HStack(spacing: 4) {
        Text("\(peer.client) · \(peer.directionText)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Spacer(minLength: 4)
        Text("↑ \(peer.upText)")
          .font(.caption)
          .monospacedDigit()
      }
      HStack(spacing: 6) {
        ProgressView(value: peer.progress)
          .tint((peer.progress >= 1 ? ColorRole.green : ColorRole.accent).color)
          .accessibilityLabel("Their progress")
        Text(peer.progressText)
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .frame(width: 34, alignment: .trailing)
      }
    }
    .padding(.vertical, 2)
  }
}
