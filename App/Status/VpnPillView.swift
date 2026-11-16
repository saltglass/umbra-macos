import SwiftUI
import UmbraKit

/// The toolbar's VPN pill: a coloured symbol and a few words, with the
/// address peers see while the VPN is connected. Clicking opens the
/// popover with the details.
struct VpnPillView: View {
  let summary: VpnSummary
  /// Asks Umbra to check the VPN again; nil in pictures of the view.
  let onCheckAgain: (() async -> Void)?
  /// Asks (always) and then starts without a VPN; nil in pictures.
  var onStartWithout: ((StartWithoutVpnConfirmation) async -> Void)?
  @State private var showsDetails = false
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Button {
      showsDetails.toggle()
    } label: {
      VpnPillContent(pill: summary.pill)
    }
    .help(summary.pill.help)
    .accessibilityLabel(summary.pill.help)
    .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
      VpnPopoverView(
        details: summary.details, onCheckAgain: onCheckAgain,
        onOpenSettings: {
          showsDetails = false
          OpenVpnSettingsAction(openSettings: openSettings)()
        },
        onStartWithout: onStartWithout.map { start in
          { question in
            showsDetails = false
            await start(question)
          }
        })
    }
  }
}

/// What is inside the pill (drawn on its own in pictures, as the
/// toolbar's glass draws blank offscreen).
struct VpnPillContent: View {
  let pill: VpnPill

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: pill.symbol)
        .foregroundStyle(pill.role.color)
      Text(pill.title)
      if let address = pill.address {
        Text(address)
          .font(.system(.body, design: .monospaced))
          .foregroundStyle(.secondary)
      }
    }
    .lineLimit(1)
    .fixedSize()
  }
}

/// The popover: the state in a sentence, a few facts, and its buttons:
/// Check Again; Open VPN Settings…; Start Without VPN… (which asks first),
/// each only where it does something.
struct VpnPopoverView: View {
  let details: VpnDetails
  let onCheckAgain: (() async -> Void)?
  var onOpenSettings: (() -> Void)?
  var onStartWithout: ((StartWithoutVpnConfirmation) async -> Void)?
  @State private var checking = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label {
        Text(details.title).font(.headline)
      } icon: {
        Image(systemName: details.symbol).foregroundStyle(details.role.color)
      }
      Text(details.sentence)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      if !details.facts.isEmpty {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
          ForEach(details.facts, id: \.label) { fact in
            GridRow {
              Text(fact.label).foregroundStyle(.secondary)
              Text(fact.value)
                .font(fact.monospaced ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
            }
          }
        }
      }
      // At most two show at once: Check Again and Open VPN Settings… while
      // the VPN is down; Open VPN Settings… and Start Without VPN… while held.
      if details.offersCheckAgain || details.offersVpnSettings || details.startWithout != nil {
        // Side by side when they fit, one under the other when they don't.
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 8) { buttons }
          VStack(alignment: .leading, spacing: 8) { buttons }
        }
      }
    }
    .padding(16)
    .frame(width: 300, alignment: .leading)
  }

  @ViewBuilder private var buttons: some View {
    if details.offersCheckAgain {
      Button("Check Again") {
        guard let onCheckAgain else { return }
        checking = true
        Task {
          await onCheckAgain()
          checking = false
        }
      }
      .disabled(checking || onCheckAgain == nil)
    }
    if details.offersVpnSettings {
      Button("Open VPN Settings…") { onOpenSettings?() }
    }
    if let question = details.startWithout {
      // Never one click: this asks first, with Cancel as the default.
      Button("Start Without VPN…") {
        Task { await onStartWithout?(question) }
      }
    }
    if checking { ProgressView().controlSize(.small) }
  }
}
