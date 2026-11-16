// Settings → Queue & Seeding: how many torrents run at once, and when a
// finished torrent has seeded enough. Two of Umbra's groups ("queue" and
// "seeding") on one page. Wording, units and what an empty box means
// follow Umbra's web page (web/src/pages/settings/BasicPages.tsx and
// SeedingPage.tsx); Umbra checks every value and says why it refuses one.

import SwiftUI
import UmbraAPI
import UmbraKit

struct QueueSeedingPage: View {
  let queue: SettingsGroupModel<Components.Schemas.QueueSettings>
  let seeding: SettingsGroupModel<Components.Schemas.SeedingSettings>

  var body: some View {
    SettingsForm(groups: [queue, seeding]) {
      Section {
        SettingsNumberRow(
          title: "Downloads at once",
          help: "Unfinished torrents downloading together. Force-started ones don't count.",
          model: queue, field: \.maxActiveDownloads, umbraName: "maxActiveDownloads",
          format: .wholeNumber())
        // 0 is no limit, shown as an empty box.
        SettingsNumberRow(
          title: "Seeds at once",
          help: "Finished torrents uploading together. Leave empty for no limit.",
          model: queue, field: \.maxActiveSeeds, umbraName: "maxActiveSeeds",
          format: .wholeNumber(blank: 0), prompt: "No limit")
      } header: {
        Text("Active torrents")
      } footer: {
        footer(
          "How many torrents run at once. The rest wait their turn, in queue order.",
          problem: queue.pageProblem)
      }

      // An empty box is no goal (nil).
      Section {
        SettingsNumberRow(
          title: "Seed ratio",
          help: "Uploaded divided by downloaded. 1 means it has shared as much as it took.",
          model: seeding, field: \.ratio, umbraName: "ratio",
          format: .optionalDecimal(), prompt: "No goal")
        SettingsNumberRow(
          title: "Seeding time",
          help: "How long it has seeded in all. A week is 168 hours.",
          model: seeding, field: \.seedingMinutes, umbraName: "seedingMinutes",
          format: .optionalHoursAsMinutes(), prompt: "No goal", unit: "hours")
        SettingsNumberRow(
          title: "Inactive for",
          help: "Seeding with nothing uploaded for this long: nobody wants it any more.",
          model: seeding, field: \.inactiveMinutes, umbraName: "inactiveMinutes",
          format: .optionalWholeNumber, prompt: "No goal", unit: "min")
      } header: {
        Text("Seeding goals")
      } footer: {
        footer(
          "When a finished torrent has shared enough; leave a goal empty to have none. The "
            + "first goal reached counts. A category's goals, or a torrent's own, come before "
            + "these. At a goal a torrent stops and stays in the list until you, or the app "
            + "that added it, remove it. Starting it again lets it seed on.",
          problem: seeding.pageProblem)
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
