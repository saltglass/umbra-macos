import AppKit
import SwiftUI
import UmbraKit

/// General: progress, the figures, where it is saved, and when it was
/// added. Everything comes from the torrent in the list, which the live
/// feed keeps up to date, so this asks Umbra for nothing.
struct GeneralTab: View {
  let model: InspectorModel
  let row: TorrentRow

  var body: some View {
    Form {
      Section { progress }

      Section("Transfer") {
        LabeledContent("Downloaded", value: row.downloadedText)
        LabeledContent("Uploaded", value: row.uploadedText)
        LabeledContent("Ratio", value: row.ratioText)
        LabeledContent("Seeds", value: row.seedsText)
        LabeledContent("Peers", value: row.peersText)
      }

      limits

      Section("Details") {
        saveLocation
        LabeledContent("Added", value: Format.longDate(row.addedAt))
        LabeledContent("Completed") {
          if let completed = row.completedAt {
            Text(Format.longDate(completed))
          } else {
            Text("Not yet").foregroundStyle(.secondary)
          }
        }
        LabeledContent("Category", value: row.categoryText)
        LabeledContent("Tags") {
          Text(row.tags.isEmpty ? Format.dash : row.tags.joined(separator: ", "))
            .multilineTextAlignment(.trailing)
        }
        infoHash
      }
    }
    .formStyle(.grouped)
    .monospacedDigit()
  }

  // MARK: Limits

  /// The torrent's own limits (none of the rows when it has none), with
  /// the button that opens the Limits sheet. Hidden until Umbra has answered.
  @ViewBuilder private var limits: some View {
    if let summary = model.limits.value {
      Section("Limits") {
        if summary.isEmpty {
          LabeledContent("Own limits") {
            Text(LimitsSummary.noneText).foregroundStyle(.secondary)
          }
        } else {
          ForEach(summary.rows) { LabeledContent($0.title, value: $0.value) }
        }
        Button("Edit…") { model.editLimits() }
          .controlSize(.small)
          .disabled(!model.connected)
          .help("Change this torrent's own speed limits and seed goals")
      }
    }
  }

  // MARK: Progress

  private var progress: some View {
    VStack(alignment: .leading, spacing: 6) {
      ProgressView(value: row.barValue)
        .tint(row.kind.barRole.color)
        .accessibilityLabel("Progress")
      if row.kind == .fetchingDetails {
        Text("Fetching details…")
          .font(.callout.weight(.medium))
      } else {
        Text(progressLine)
          .font(.callout.weight(.medium))
      }
      Text(speedLine)
        .font(.callout)
        .foregroundStyle(.secondary)
      if let note = row.note {
        Text(note.text)
          .font(.callout)
          .foregroundStyle(note.role.color)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      } else if row.kind == .paused, let reason = row.error {
        // A paused torrent's error is the seed goal it stopped at.
        Text(reason)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      if row.kind == .missingFiles {
        Button("Download Again") { Task { await model.downloadAgain() } }
          .buttonStyle(.bordered)
          .help("Check the files and download whatever is missing")
          .padding(.top, 2)
      }
    }
  }

  /// "34% · 1.2 GB of 3.4 GB · ETA 41m"
  private var progressLine: String {
    let have = Format.bytes(Double(row.size) * row.progress)
    var line = "\(row.progressText) · \(have) of \(row.sizeText)"
    if let eta = row.etaSeconds, eta > 0 { line += " · ETA \(row.etaText)" }
    return line
  }

  /// "↓ 8.4 MB/s · ↑ 120 KB/s", or the status when it isn't running.
  private var speedLine: String {
    switch row.kind {
    case .paused, .queued, .waitingForVpn, .waitingForSpace, .missingFiles:
      return row.statusLabel
    default:
      return
        "↓ \(Format.speed(row.downSpeed, zero: "0 B/s")) · ↑ \(Format.speed(row.upSpeed, zero: "0 B/s"))"
    }
  }

  // MARK: Details

  private var saveLocation: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Save to")
      Text(row.savePath)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
      Button("Show in Finder", systemImage: "folder") { showInFinder() }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!FileManager.default.fileExists(atPath: row.savePath))
    }
  }

  /// Selects the torrent's own file or folder in Finder; if that isn't
  /// there (a magnet still waiting, say), opens the save folder instead.
  private func showInFinder() {
    let folder = URL(fileURLWithPath: row.savePath)
    let item = folder.appending(path: row.name)
    let target = FileManager.default.fileExists(atPath: item.path) ? item : folder
    NSWorkspace.shared.activateFileViewerSelecting([target])
  }

  private var infoHash: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Info hash")
        Spacer()
        Button("Copy", systemImage: "doc.on.doc") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(row.hash, forType: .string)
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Copy the info hash")
      }
      Text(row.hash)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }
  }
}
