// Settings → VPN: the VPN's state, the saved WireGuard VPNs, adding one,
// what happens when the one in use is down, and what is true while no VPN
// is in use. Wording follows Umbra's web page
// (web/src/pages/settings/VpnPage.tsx).
//
// The VPN isn't one of Umbra's settings groups: `VpnSettingsModel` (in
// UmbraKit) does its requests, one at a time, and reads the state back
// after each. Umbra decides everything: the kill switch is always on and
// isn't a setting here, and "Start Without VPN" only ever asks Umbra, after
// asking the person (Cancel is the default).
//
// A VPN configuration holds a private key. It goes from the file chosen,
// or the text pasted, straight to Umbra, and the Mac keeps no copy.

import SwiftUI
import UmbraAPI
import UmbraKit

struct VpnPage: View {
  let model: VpnSettingsModel

  @State private var sheet: VpnSheet?
  /// The saved VPN waiting for "Remove" to be confirmed, by id.
  @State private var removing: String?
  @State private var addingFile = false
  /// A file is being dragged over the page.
  @State private var dropTargeted = false

  var body: some View {
    SettingsForm(groups: [model]) {
      statusSection
      savedSection
      if model.status?.configured == true {
        whenDownSection
      }
      if let situation = model.noVpnSituation {
        noVpnSection(situation)
      }
    }
    // Dropping .conf files on the page adds them, as Add from File… does:
    // each is read once, sent to Umbra and dropped. Only files are taken.
    .dropDestination(for: URL.self) { urls, _ in
      let files = urls.filter(\.isFileURL)
      guard !files.isEmpty else { return false }
      Task { for url in files { await model.add(fileAt: url) } }
      return true
    } isTargeted: {
      dropTargeted = $0
    }
    .overlay {
      if dropTargeted {
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(Color.accentColor, lineWidth: 3)
          .padding(4)
          .allowsHitTesting(false)
      }
    }
    .sheet(item: $sheet) { sheet in
      switch sheet {
      case .paste(let refusal):
        VpnPasteSheet(model: model, refusal: refusal)
      case .edit(let id):
        if let vpn = model.saved.first(where: { $0.id == id }) {
          VpnEditSheet(model: model, vpn: vpn)
        }
      }
    }
    .alert(
      removeQuestion?.title ?? "",
      isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
      presenting: removeQuestion
    ) { question in
      Button("Cancel", role: .cancel) {}
      Button(question.button, role: .destructive) {
        if let id = removing { model.remove(id) }
      }
    } message: { question in
      Text(question.message)
    }
  }

  private var removeQuestion: VpnSettingsModel.RemoveQuestion? {
    removing.flatMap { model.removeQuestion(for: $0) }
  }

  // MARK: Status

  /// The same state, address, forwarded port and "last changed" the
  /// toolbar pill's popover shows, with Check Again.
  private var statusSection: some View {
    let details = model.summary().details
    return Section {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Image(systemName: details.symbol)
          .foregroundStyle(details.role.color)
          .font(.title3)
        VStack(alignment: .leading, spacing: 3) {
          Text(details.title).font(.headline)
          Text(details.sentence)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 8)
        if details.offersCheckAgain {
          Button("Check Again") { model.checkAgain() }
            .disabled(model.isChecking)
        }
      }
      ForEach(details.facts.filter { !(inUse != nil && $0.label == "Forwarded port") }, id: \.label)
      { fact in
        LabeledContent(fact.label) {
          Text(fact.value)
            .font(fact.monospaced ? .system(.body, design: .monospaced) : .body)
            .textSelection(.enabled)
        }
      }
      if let inUse {
        ForwardedPortRow(model: model, port: inUse.forwardedPort ?? 0)
      }
      if let switched = lastSwitch {
        Label(switched, systemImage: "arrow.triangle.swap")
          .foregroundStyle(.secondary)
      }
    } header: {
      Text("Status")
    } footer: {
      SettingsFooter(
        "Every torrent goes through a WireGuard tunnel. If it drops, torrents stop: nothing "
          + "falls back to this Mac's own connection.")
    }
  }

  /// The saved VPN in use, whose forwarded port the Status section sets.
  private var inUse: Components.Schemas.VpnProfile? {
    model.status?.saved.first(where: \.inUse)
  }

  /// "Switched here from … at …", when switching (not the person) put the
  /// VPN in use there.
  private var lastSwitch: String? {
    guard let status = model.status, let last = status.lastSwitch,
      last.toId == status.saved.first(where: \.inUse)?.id
    else { return nil }
    let minutes = last.minutes == 1 ? "1 minute" : "\(last.minutes) minutes"
    let time = last.at.formatted(date: .abbreviated, time: .shortened)
    return "Switched here from “\(last.fromName)” on \(time): it was down for \(minutes)."
  }

  // MARK: Saved VPNs

  private var savedSection: some View {
    Section {
      if model.saved.isEmpty {
        Text("No VPNs saved")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
      }
      ForEach(model.saved, id: \.id) { vpn in
        savedRow(vpn)
      }
      .onMove { from, to in model.move(fromOffsets: from, toOffset: to) }
      HStack {
        Button("Add from File…", systemImage: "doc.badge.plus") { addFromFile() }
        Button("Paste Configuration…", systemImage: "doc.on.clipboard") {
          sheet = .paste(nil)
        }
        Spacer()
        if model.isSending { ProgressView().controlSize(.small) }
      }
    } header: {
      Text("Saved VPNs")
    } footer: {
      VStack(alignment: .leading, spacing: 6) {
        Text(
          "Add the .conf files from your VPN provider, or drag them onto this page. Umbra "
            + "stores their private keys encrypted and never shows them again. Switching "
            + "tries them from the top: drag a saved VPN to change the order."
        )
        .foregroundStyle(.secondary)
        SettingsProblem(message: model.refusal.map(VpnSettingsModel.explanation))
      }
      .font(.callout)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func savedRow(_ vpn: Components.Schemas.VpnProfile) -> some View {
    HStack(spacing: 10) {
      rowSymbol(vpn)
      VStack(alignment: .leading, spacing: 2) {
        Text(vpn.name).lineLimit(1)
        if let problem = vpn.problem, !problem.isEmpty {
          Text(problem).foregroundStyle(.red).font(.callout)
        } else if let detail = detail(of: vpn) {
          Text(detail).foregroundStyle(.secondary).font(.callout).lineLimit(1)
        }
      }
      Spacer(minLength: 8)
      if !vpn.inUse {
        Button("Use") { model.use(vpn.id) }
          .disabled(vpn.problem != nil || model.isSending)
          .help("Put \(vpn.name) in use. Every torrent pauses for a few seconds.")
      }
      Menu {
        rowMenu(vpn)
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .menuStyle(.button)
      .buttonStyle(.borderless)
      .menuIndicator(.hidden)
      .fixedSize()
      .help("More for \(vpn.name)")
    }
    .contextMenu { rowMenu(vpn) }
  }

  /// A filled shield for the one in use, an outline for the others, and a
  /// warning for one Umbra can't use.
  @ViewBuilder private func rowSymbol(_ vpn: Components.Schemas.VpnProfile) -> some View {
    if let problem = vpn.problem, !problem.isEmpty {
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
    } else if vpn.inUse {
      Image(systemName: "lock.shield.fill").foregroundStyle(.green)
    } else {
      Image(systemName: "lock.shield").foregroundStyle(.secondary)
    }
  }

  /// "In use", "Next in line", then where it connects and its forwarded port.
  private func detail(of vpn: Components.Schemas.VpnProfile) -> String? {
    var parts: [String] = []
    if vpn.inUse {
      parts.append("In use")
    } else if vpn.id == model.nextInLine?.id {
      parts.append("Next in line")
    }
    if let endpoint = vpn.endpoint, !endpoint.isEmpty { parts.append(endpoint) }
    if let port = vpn.forwardedPort, port > 0 { parts.append("port \(port) forwarded") }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  @ViewBuilder private func rowMenu(_ vpn: Components.Schemas.VpnProfile) -> some View {
    Button("Rename or Edit…") { sheet = .edit(vpn.id) }
    Button("Move Up") { model.move(vpn.id, by: -1) }
      .disabled(!model.canMove(vpn.id, by: -1))
    Button("Move Down") { model.move(vpn.id, by: 1) }
      .disabled(!model.canMove(vpn.id, by: 1))
    Divider()
    Button("Remove…", role: .destructive) { removing = vpn.id }
  }

  /// The system's open panel for a .conf file. The file is read only after
  /// it is chosen, sent to Umbra, and dropped.
  private func addFromFile() {
    Task {
      guard let url = await ConfigFilePanel.choose() else { return }
      await model.add(fileAt: url)
    }
  }

  // MARK: When the VPN in use is down

  private var whenDownSection: some View {
    Section {
      Label {
        Text("Every torrent stops until it reconnects.")
        Text("Always on. Nothing falls back to this Mac's own connection.")
      } icon: {
        Image(systemName: "lock.shield.fill").foregroundStyle(.green)
      }
      Toggle(isOn: failoverBinding) {
        Text("Switch to the next saved VPN")
        Text(
          model.saved.count > 1
            ? "If the VPN in use is down for this long, Umbra tries the next one in the list, and "
              + "keeps going round it until one connects. It never switches back by itself."
            : "Save a second VPN for this to do anything.")
      }
      if model.status?.failover.enabled == true {
        FailoverMinutesRow(model: model)
      }
    } header: {
      Text("When the VPN in use is down")
    }
  }

  private var failoverBinding: Binding<Bool> {
    Binding(
      get: { model.status?.failover.enabled ?? false },
      set: { model.setFailover(enabled: $0) })
  }

  // MARK: No VPN in use

  private func noVpnSection(_ situation: VpnSettingsModel.NoVpnSituation) -> some View {
    Section {
      Text(situation.text)
        .fixedSize(horizontal: false, vertical: true)
      if let question = model.startWithout {
        LabeledContent {
          Button("Start Without VPN…") {
            Task {
              // Always asked first; Cancel is the default.
              if await VpnPrompts.confirmStartWithout(question) { model.startWithoutVpn() }
            }
          }
        } label: {
          Text("Start without a VPN")
          Text("Peers will see this Mac's real IP address.")
        }
      }
    } header: {
      Text("No VPN in use")
    }
  }
}

/// The forwarded port of the VPN in use: typed, sent on Return or on
/// leaving the box; empty is none. A value Umbra refuses goes back, with
/// its words under the label. (The Edit sheet sets any saved VPN's.)
private struct ForwardedPortRow: View {
  let model: VpnSettingsModel
  /// What Umbra has now; 0 is none.
  let port: Int
  @State private var text: String?
  @State private var problem: String?
  @FocusState private var focused: Bool

  var body: some View {
    LabeledContent {
      TextField(
        "Forwarded port",
        text: Binding(get: { text ?? (port > 0 ? String(port) : "") }, set: { text = $0 }),
        prompt: Text("None")
      )
      .labelsHidden()
      .textFieldStyle(.roundedBorder)
      .multilineTextAlignment(.trailing)
      .monospacedDigit()
      .frame(width: 80)
      .focused($focused)
      .onSubmit(commit)
    } label: {
      Text("Forwarded port")
      Text("The port your VPN provider forwards to you, so peers can connect in. Empty: none.")
      SettingsProblem(message: problem ?? model.refusal?.fields["forwardedPort"])
    }
    .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    .onDisappear(perform: commit)
  }

  private func commit() {
    guard let typed = text else { return }
    text = nil
    let trimmed = typed.trimmingCharacters(in: .whitespaces)
    guard let number = trimmed.isEmpty ? 0 : Int(trimmed) else {
      problem = "A port is a whole number."
      return
    }
    problem = nil
    model.setForwardedPort(number)
  }
}

/// "after N minutes": typed, sent on Return or on leaving the box; a value
/// Umbra refuses goes back, with its words under the label.
private struct FailoverMinutesRow: View {
  let model: VpnSettingsModel
  @State private var text: String?
  @FocusState private var focused: Bool

  var body: some View {
    LabeledContent {
      HStack(spacing: 6) {
        TextField(
          "Minutes",
          text: Binding(
            get: { text ?? model.status.map { String($0.failover.minutes) } ?? "" },
            set: { text = $0 })
        )
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
        .frame(width: 80)
        .focused($focused)
        .onSubmit(commit)
        Text("min")
          .foregroundStyle(.secondary)
          .frame(width: 40, alignment: .leading)
      }
    } label: {
      Text("After it has been down for")
      SettingsProblem(message: model.refusal?.fields["minutes"])
    }
    .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    .onDisappear(perform: commit)
  }

  private func commit() {
    guard let typed = text else { return }
    text = nil
    if case .value(let minutes) = SettingsFormat<Int>.wholeNumber().read(typed) {
      model.setFailover(minutes: minutes)
    }
  }
}

/// A grey explanation under a section.
struct SettingsFooter: View {
  let text: String
  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text)
      .foregroundStyle(.secondary)
      .font(.callout)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
