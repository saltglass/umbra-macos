// Settings → Connection: the port other peers connect to, and how peers
// are found. One of Umbra's groups ("connection"). Wording follows Umbra's
// web page (web/src/pages/settings/BasicPages.tsx); Umbra checks the port
// and says why it refuses one.

import SwiftUI
import UmbraAPI
import UmbraKit

struct ConnectionPage: View {
  let model: SettingsGroupModel<Components.Schemas.ConnectionSettings>

  var body: some View {
    SettingsForm(groups: [model]) {
      Section {
        SettingsNumberRow(
          title: "Peer port",
          help: "The port other peers connect to, TCP and UDP, without a VPN. Behind a VPN, "
            + "peers use the port it forwards (see the VPN page).",
          model: model, field: \.listenPort, umbraName: "listenPort",
          format: .wholeNumber())
      } header: {
        Text("Incoming connections")
      } footer: {
        footer(
          "How peers reach Umbra. Umbra never opens a port on your router.",
          problem: model.pageProblem)
      }

      Section {
        SettingsToggleRow(
          title: "DHT",
          help: "Find peers without a tracker. Private torrents never use it.",
          model: model, field: \.dht, umbraName: "dht")
        SettingsToggleRow(
          title: "Peer exchange",
          help: "Learn about more peers from the ones connected. Private torrents never use it.",
          model: model, field: \.pex, umbraName: "pex")
      } header: {
        Text("Finding peers")
      }
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
