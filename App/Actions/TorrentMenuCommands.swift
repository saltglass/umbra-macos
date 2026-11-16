import SwiftUI
import UmbraKit

/// The menu bar's Torrent menu, drawn from the same description as the
/// right-click menu (`TorrentMenu`).
struct TorrentMenuCommands: Commands {
  let model: MainWindowModel
  let runner: TorrentCommandRunner

  var body: some Commands {
    CommandMenu(TorrentMenu.title) {
      TorrentMenuContent(model: model, runner: runner)
    }
  }
}

/// The menu's content as a view of its own, so SwiftUI redraws the menu
/// when the selection, the categories or slow mode change.
struct TorrentMenuContent: View {
  let model: MainWindowModel
  let runner: TorrentCommandRunner

  var body: some View {
    let menu = model.torrentMenu(connected: runner.connected)
    TorrentMenuEntries(entries: menu.menuBarEntries, run: runner.run)
    Divider()
    PauseResumeAllItems(menuBar: runner.menuBar)
  }
}

/// Pause All (⌥⌘.) and Resume All (⌥⌘/): the same two actions as the menu
/// bar item's panel, on every torrent rather than the selection. A refusal
/// shows in the window's alert, like any other menu action's.
private struct PauseResumeAllItems: View {
  let menuBar: MenuBarModel

  var body: some View {
    let summary = menuBar.summary
    Button("Pause All", systemImage: "pause") {
      Task { menuBar.alert(await menuBar.pauseAll()) }
    }
    .keyboardShortcut(".", modifiers: [.command, .option])
    .disabled(!summary.canPauseAll)
    Button("Resume All", systemImage: "play") {
      Task { menuBar.alert(await menuBar.resumeAll()) }
    }
    .keyboardShortcut("/", modifiers: [.command, .option])
    .disabled(!summary.canResumeAll)
  }
}

/// A list of menu entries; a submenu draws its own entries the same way.
struct TorrentMenuEntries: View {
  let entries: [TorrentMenuEntry]
  let run: (TorrentMenuCommand) -> Void

  var body: some View {
    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
      switch entry {
      case .separator:
        Divider()
      case .item(let item):
        TorrentMenuButton(item: item, run: run)
      case .submenu(let title, let symbol, let enabled, let entries):
        Menu {
          TorrentMenuEntries(entries: entries, run: run)
        } label: {
          if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
        }
        .disabled(!enabled)
      }
    }
  }
}

/// One item: a button, or (when it can carry a tick) a toggle, whose
/// check mark shows the state. A mixed state shows a dash.
private struct TorrentMenuButton: View {
  let item: TorrentMenuItem
  let run: (TorrentMenuCommand) -> Void

  var body: some View {
    control
      .keyboardShortcut(item.shortcut)
      .disabled(!item.enabled)
  }

  @ViewBuilder private var control: some View {
    switch item.mark {
    case .on, .off:
      Toggle(
        item.title,
        isOn: Binding(get: { item.mark == .on }, set: { _ in run(item.command) }))
    case .mixed:
      Button(item.title, systemImage: "minus") { run(item.command) }
    case .none:
      if let symbol = item.symbol {
        Button(item.title, systemImage: symbol) { run(item.command) }
      } else {
        Button(item.title) { run(item.command) }
      }
    }
  }
}

extension View {
  /// Applies an item's shortcut, if it has one.
  @ViewBuilder fileprivate func keyboardShortcut(_ shortcut: MenuShortcut?) -> some View {
    if let shortcut {
      keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.modifiers)
    } else {
      self
    }
  }
}

extension MenuShortcut {
  fileprivate var keyEquivalent: KeyEquivalent {
    switch key {
    case .character(let c): KeyEquivalent(c)
    case .delete: .delete
    }
  }

  fileprivate var modifiers: EventModifiers {
    var modifiers: EventModifiers = [.command]
    if shift { modifiers.insert(.shift) }
    if option { modifiers.insert(.option) }
    return modifiers
  }
}
