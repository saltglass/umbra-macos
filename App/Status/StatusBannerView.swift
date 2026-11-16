import SwiftUI
import UmbraKit

/// The notices above the list, stacked, most important first. Each is one
/// line (longer words wrap) in the style of the system's own inline notices:
/// a coloured symbol, plain text on a material, and a button where one works.
struct StatusBanners: View {
  let banners: [StatusBanner]
  /// The quiet "Reconnecting…" line, shown below the banners.
  let connectionNote: String?
  /// Carries out a banner's button.
  let onAction: (StatusBanner.Action) async -> Void

  var body: some View {
    VStack(spacing: 0) {
      ForEach(banners) { banner in
        StatusBannerView(banner: banner, onAction: onAction)
        Divider()
      }
      if let connectionNote {
        ConnectionNoteView(text: connectionNote)
        Divider()
      }
    }
  }
}

struct StatusBannerView: View {
  let banner: StatusBanner
  let onAction: (StatusBanner.Action) async -> Void
  @State private var busy = false

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: banner.symbol)
        .foregroundStyle(banner.role.color)
      Text(banner.message)
        // No `fixedSize` here: it made the banner's smallest height that of
        // its words wrapped into no width at all, taller than the window,
        // and the split view then crashed trying to fit it (2026-11-13).
        .lineLimit(3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
      ForEach(banner.actions, id: \.title) { action in
        Button(action.title) {
          busy = true
          Task {
            await onAction(action)
            busy = false
          }
        }
        .controlSize(.small)
        .fixedSize()
        .disabled(busy)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .background(.regularMaterial)
    .accessibilityElement(children: .combine)
  }
}

/// A small, calm line: Umbra isn't answering for the moment and the app is
/// trying again. The list below it stays as it was.
struct ConnectionNoteView: View {
  let text: String

  var body: some View {
    HStack(spacing: 6) {
      ProgressView().controlSize(.mini)
      Text(text)
    }
    .font(.subheadline)
    .foregroundStyle(.secondary)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 4)
    .background(.bar)
  }
}
