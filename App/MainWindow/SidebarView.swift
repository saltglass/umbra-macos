import SwiftUI
import UmbraKit

/// The sidebar: the status filters, then categories, tags and trackers,
/// each with its count, and the free disk space at the bottom.
struct SidebarView: View {
  @Bindable var model: MainWindowModel
  /// "412 GB free"; nil hides the line.
  let freeSpace: String?

  var body: some View {
    // The free-space line sits under the list, not over it, so it never
    // covers the last rows.
    VStack(spacing: 0) {
      list
      if let freeSpace {
        Label(freeSpace, systemImage: "internaldrive")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
      }
    }
  }

  private var list: some View {
    List(selection: filterSelection) {
      ForEach(model.sidebarSections) { section in
        if let title = section.title {
          Section(title) { rows(section) }
        } else {
          Section { rows(section) }
        }
      }
    }
    .listStyle(.sidebar)
  }

  private func rows(_ section: SidebarSection) -> some View {
    ForEach(section.items) { item in
      Label {
        Text(item.title)
      } icon: {
        // The Errors row turns red while anything is in it.
        if item.isAlert {
          Image(systemName: item.symbolName).foregroundStyle(.red)
        } else {
          Image(systemName: item.symbolName)
        }
      }
      .badge(item.count)
      .tag(item.filter)
    }
  }

  /// The list's selection is the window's filter (there is always one).
  private var filterSelection: Binding<TorrentFilter?> {
    Binding(get: { model.filter }, set: { if let filter = $0 { model.filter = filter } })
  }
}
