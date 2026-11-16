// Settings → Notifications: email when something happens that you'd want
// to hear about, sent through a mail service you already have. One of
// Umbra's groups ("notifications"). Wording follows Umbra's web page
// (web/src/pages/settings/NotificationsPage.tsx); Umbra checks every
// value and says why it refuses one.
//
// The mail password is a secret: Umbra never sends it back, only whether
// one is stored. So the page shows "Set" or "Not set", a box for a new
// one (sent when you press Return or leave the box, then the box empties)
// and a Remove button. The Mac keeps no copy of it.

import SwiftUI
import UmbraAPI
import UmbraKit

struct NotificationsPage: View {
  let model: SettingsGroupModel<NotificationsDraft>
  /// The result of the last "Send a Test". The running app starts it
  /// empty; pictures hand in a fixed one.
  @State private var test: NotificationTestModel

  init(
    model: SettingsGroupModel<NotificationsDraft>, test: NotificationTestModel = .init()
  ) {
    self.model = model
    _test = State(initialValue: test)
  }

  @Environment(\.settingsSource) private var source
  @State private var confirmingRemoval = false

  var body: some View {
    SettingsForm(groups: [model]) {
      Section {
        SettingsToggleRow(
          title: "Send emails",
          help: "Fill in the mail server first, then turn this on.",
          model: model, field: \.settings.enabled, umbraName: "enabled")
      } header: {
        Text("Email")
      } footer: {
        footer(
          "Email when something happens you'd want to know about, sent through a mail "
            + "service you already have. Umbra runs no mail server of its own.",
          problem: model.pageProblem)
      }

      Section {
        SettingsTextRow(
          title: "Server", model: model, field: \.settings.host, umbraName: "host",
          format: .text, prompt: "smtp.example.com")
        securityMenu
        SettingsNumberRow(
          title: "Port", help: "Follows Security, above, unless you've set another.",
          model: model, field: \.settings.port, umbraName: "port",
          format: .wholeNumber())
        SettingsTextRow(
          title: "Username",
          help: "Usually your email address. Leave empty for a relay that takes no password.",
          model: model, field: \.settings.username, umbraName: "username", format: .text)
        passwordStatus
        SettingsTextRow(
          title: "New password",
          help:
            "Sent only to Umbra, which sends it to the mail server over an encrypted connection.",
          model: model, field: \.password, umbraName: "password", format: .newSecret,
          prompt: "Type to replace", secret: true)
        SettingsTextRow(
          title: "From",
          help: "The address the emails come from. Your provider may insist it's your own.",
          model: model, field: \.settings.from, umbraName: "from", format: .text,
          prompt: "umbra@example.com")
        SettingsTextRow(
          title: "To", help: "Where they go. Several addresses are separated by commas.",
          model: model, field: \.settings.to, umbraName: "to", format: .text,
          prompt: "you@example.com")
        testRow
      } header: {
        Text("Mail server")
      } footer: {
        Text(
          "Your email provider's SMTP settings; its help pages list them. Many providers want "
            + "an app password here, not your usual one."
        )
        .foregroundStyle(.secondary)
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      Section {
        SettingsToggleRow(
          title: "A download finishes",
          help: "Several finishing together come in one email. Torrents whose files were "
            + "already on disk don't count.",
          model: model, field: \.settings.onFinished, umbraName: "onFinished")
        SettingsToggleRow(
          title: "A torrent has a problem",
          help: "An error, or its files gone missing; also every torrent stopped, by another "
            + "program on the peer port, say.",
          model: model, field: \.settings.onError, umbraName: "onError")
        SettingsToggleRow(
          title: "The VPN is down",
          help: "Once it has been down for 5 minutes, and again when it's back.",
          model: model, field: \.settings.onVpn, umbraName: "onVpn")
        SettingsToggleRow(
          title: "The disk is nearly full",
          help: "Below the level Downloads keeps free, when new downloads start to wait.",
          model: model, field: \.settings.onLowDisk, umbraName: "onLowDisk")
      } header: {
        Text("Email me when")
      }
    }
    // The last result says nothing about settings changed since.
    .onChange(of: model.value?.settings) { test.clear() }
  }

  // MARK: Rows

  /// How to talk to the mail server; sent at once. The port follows the
  /// choice (see `chooseSecurity`).
  private var securityMenu: some View {
    Picker(
      selection: Binding(
        get: { model.value?.security ?? "starttls" },
        set: { choice in model.change { $0.chooseSecurity(choice) } })
    ) {
      ForEach(MailSecurityChoice.all) { Text($0.label).tag($0.id) }
    } label: {
      Text("Security")
      SettingsProblem(message: model.problem(for: "security"))
    }
  }

  /// Whether a password is stored, with a button to remove it.
  private var passwordStatus: some View {
    let isSet = model.value?.passwordIsSet ?? false
    return LabeledContent {
      HStack {
        Text(isSet ? "Set" : "Not set")
          .foregroundStyle(.secondary)
        if isSet {
          Button("Remove") { confirmingRemoval = true }
            .confirmationDialog(
              "Remove the mail password?", isPresented: $confirmingRemoval
            ) {
              Button("Remove", role: .destructive) {
                model.set(\.password, to: .removed)
              }
            } message: {
              Text("Umbra will send email without a password until you enter a new one.")
            }
        }
      }
    } label: {
      Text("Password")
      SettingsProblem(message: model.problem(for: "password"))
    }
  }

  /// "Send a Test": tries the settings as they are now with the mail
  /// server and says what happened, in Umbra's words.
  private var testRow: some View {
    LabeledContent {
      Button {
        if let draft = model.value {
          test.send(draft, using: source?.settingsActions)
        }
      } label: {
        Label("Send", systemImage: "paperplane")
      }
      .disabled(!(model.value?.canSendTest ?? false) || test.isSending)
    } label: {
      Text("Send a test email")
      Text("Checks the settings above with your mail server, now.")
      testResult
    }
  }

  @ViewBuilder private var testResult: some View {
    switch test.state {
    case .idle:
      EmptyView()
    case .sending:
      HStack(spacing: 6) {
        ProgressView().controlSize(.small)
        Text("Sending…")
      }
    case .sent:
      Label(
        "Sent to \(model.value?.settings.to ?? "you"). If it doesn't arrive, look in spam.",
        systemImage: "checkmark.circle.fill"
      )
      .foregroundStyle(.green)
    case .failed(let message):
      SettingsProblem(message: message)
    }
  }

  /// A section's explanation, with Umbra's message under it when it
  /// refused a change without naming a field.
  private func footer(_ text: String, problem: String?) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(text)
        .foregroundStyle(.secondary)
      SettingsProblem(message: problem)
    }
    .font(.callout)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
