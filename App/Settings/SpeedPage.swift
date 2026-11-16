// Settings → Speed: the download and upload limits, slow mode (a second,
// lower pair of limits) and the schedule that switches slow mode on and
// off. One of Umbra's groups ("speed"). Wording follows Umbra's web page
// (web/src/pages/settings/SpeedPage.tsx); Umbra checks every value.
//
// The slow mode switch here and the tortoise button in the main window's
// toolbar are the same setting: when the toolbar changes it, Umbra says the
// "speed" group changed and this page's model reads it again.

import SwiftUI
import UmbraAPI
import UmbraKit

struct SpeedPage: View {
  typealias Settings = Components.Schemas.SpeedSettings

  let speed: SettingsGroupModel<Settings>

  /// Umbra keeps limits in KB/s; the page shows MB/s, as the web page does.
  /// Empty (shown as "No limit") is 0.
  private let limit = SettingsFormat<Int>.megabytesPerSecond()

  var body: some View {
    SettingsForm(groups: [speed]) {
      Section {
        SettingsNumberRow(
          title: "Download limit",
          help: "The most Umbra will download at once. Leave empty for no limit.",
          model: speed, field: \.downloadLimitKBs, umbraName: "downloadLimitKBs",
          format: limit, prompt: "No limit", unit: "MB/s")
        SettingsNumberRow(
          title: "Upload limit",
          help: "The most Umbra will upload at once. Leave empty for no limit.",
          model: speed, field: \.uploadLimitKBs, umbraName: "uploadLimitKBs",
          format: limit, prompt: "No limit", unit: "MB/s")
      } header: {
        Text("Limits")
      } footer: {
        footer(
          "What Umbra may use all the time. Limits apply to all torrents together.",
          problem: speed.pageProblem)
      }

      Section {
        SettingsToggleRow(
          title: "Slow mode",
          help: "Use the lower limits now. The tortoise button in the toolbar does the same.",
          model: speed, field: \.slowMode, umbraName: "slowMode")
        SettingsNumberRow(
          title: "Slow-mode download limit",
          help: "Used while slow mode is on.",
          model: speed, field: \.slowDownloadKBs, umbraName: "slowDownloadKBs",
          format: limit, prompt: "No limit", unit: "MB/s")
        SettingsNumberRow(
          title: "Slow-mode upload limit",
          help: "Used while slow mode is on.",
          model: speed, field: \.slowUploadKBs, umbraName: "slowUploadKBs",
          format: limit, prompt: "No limit", unit: "MB/s")
      } header: {
        Label("Slow mode", systemImage: "tortoise")
      }

      Section {
        SettingsToggleRow(
          title: "Turn slow mode on a schedule",
          help: "Switches it on and off for you, on the days and hours below.",
          model: speed, field: \.slowModeSchedule.enabled, umbraName: "slowModeSchedule.enabled")
        if let schedule = speed.value?.slowModeSchedule, schedule.enabled {
          daysRow(schedule)
          timeRow("From", field: \.slowModeSchedule.from, umbraName: "slowModeSchedule.from")
          timeRow(
            "To", help: "Earlier than From: it runs past midnight, into the next morning.",
            field: \.slowModeSchedule.to, umbraName: "slowModeSchedule.to")
          SettingsProblem(message: speed.problem(for: "slowModeSchedule.days"))
        }
      } header: {
        Label("Schedule", systemImage: "calendar.badge.clock")
      } footer: {
        if let schedule = speed.value?.slowModeSchedule, schedule.enabled {
          footer(
            ScheduleSummary.text(days: schedule.days, from: schedule.from, to: schedule.to),
            problem: nil)
        }
      }
    }
  }

  /// Seven small toggles, Monday first, each lit while that day is on.
  private func daysRow(_ schedule: Settings.slowModeSchedulePayload) -> some View {
    LabeledContent("Days") {
      HStack(spacing: 4) {
        ForEach(ScheduleDays.displayOrder, id: \.self) { day in
          Toggle(
            ScheduleDays.shortName(of: day),
            isOn: Binding(
              get: { schedule.days.contains(day) },
              set: { on in
                // Applied to the newest copy, so quick clicks on two days both count.
                speed.change {
                  $0.slowModeSchedule.days = ScheduleDays.setting(
                    day, on: on, in: $0.slowModeSchedule.days)
                }
              })
          )
          .toggleStyle(.button)
          .controlSize(.small)
          .accessibilityLabel(ScheduleDays.name(of: day))
        }
      }
    }
  }

  /// A time of day in the system's own picker, kept as Umbra's "HH:MM".
  private func timeRow(
    _ title: String, help: String? = nil, field: WritableKeyPath<Settings, String>,
    umbraName: String
  ) -> some View {
    DatePicker(
      selection: Binding(
        get: {
          ClockTime.date(from: speed.value?[keyPath: field] ?? "")
            ?? Calendar.current.startOfDay(for: Date())
        },
        set: { speed.set(field, to: ClockTime.text(from: $0)) }),
      displayedComponents: .hourAndMinute
    ) {
      Text(title)
      if let help { Text(help) }
      SettingsProblem(message: speed.problem(for: umbraName))
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
