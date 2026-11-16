import SwiftUI
import UmbraKit

/// What the window shows in place of the list while Umbra isn't running:
/// starting, restarting (before there is a list to keep showing), saving at
/// Quit, or the reason it couldn't run. Centred and calm.
///
/// There is no Try Again button on the failure screen: the app has no way
/// to restart a helper that has given up (`AppSession` only starts once),
/// so a button would do nothing. Quit and open Umbra again.
struct SessionStateView: View {
  let phase: AppSession.Phase

  var body: some View {
    switch phase {
    case .starting, .running:
      waiting("Starting…", detail: "Getting Umbra ready.")
    case .reconnecting:
      waiting("Reconnecting…", detail: "Umbra stopped and is starting again.")
    case .saving:
      waiting("Saving…", detail: "Umbra is saving your torrents before it closes.")
    case .stopped:
      ContentUnavailableView("Umbra has stopped", systemImage: "stop.circle")
    case .failed(let message, let logTail):
      FailureView(message: message, logTail: logTail)
    }
  }

  private func waiting(_ title: String, detail: String) -> some View {
    VStack(spacing: 12) {
      ProgressView().controlSize(.large)
      Text(title).font(.title3.weight(.semibold))
      Text(detail).foregroundStyle(.secondary)
    }
    .multilineTextAlignment(.center)
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// Why Umbra couldn't run, with the end of its log to read or copy.
struct FailureView: View {
  let message: String
  let logTail: [String]

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 34))
        .foregroundStyle(ColorRole.orange.color)
      Text("Umbra couldn't run").font(.title3.weight(.semibold))
      Text(message)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
      if !logTail.isEmpty {
        ScrollView {
          Text(logTail.joined(separator: "\n"))
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .frame(maxWidth: 520, minHeight: 0, maxHeight: min(180, CGFloat(logTail.count) * 15 + 20))
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
        .accessibilityLabel("The end of Umbra's log")
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
