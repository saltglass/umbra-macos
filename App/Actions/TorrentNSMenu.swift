import AppKit
import UmbraKit

/// A menu item that remembers what choosing it does.
final class TorrentMenuNSItem: NSMenuItem {
  var command: TorrentMenuCommand?
}

/// Draws the torrent menu description as an AppKit menu (the right-click
/// menu). The menu bar's version draws the same description in SwiftUI
/// (`TorrentMenuCommands`), so the two never disagree.
@MainActor
enum TorrentNSMenu {
  /// `target` receives `action` with the chosen `TorrentMenuNSItem`.
  static func make(
    _ entries: [TorrentMenuEntry], title: String = TorrentMenu.title, target: AnyObject?,
    action: Selector
  ) -> NSMenu {
    let menu = NSMenu(title: title)
    // The description says what is enabled; AppKit must not second-guess it.
    menu.autoenablesItems = false
    for entry in entries {
      switch entry {
      case .separator:
        menu.addItem(.separator())
      case .item(let item):
        menu.addItem(makeItem(item, target: target, action: action))
      case .submenu(let title, let symbol, let enabled, let entries):
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.image = image(symbol)
        parent.isEnabled = enabled
        parent.submenu = make(entries, title: title, target: target, action: action)
        menu.addItem(parent)
      }
    }
    return menu
  }

  private static func makeItem(
    _ item: TorrentMenuItem, target: AnyObject?, action: Selector
  ) -> TorrentMenuNSItem {
    let ns = TorrentMenuNSItem(title: item.title, action: action, keyEquivalent: "")
    ns.command = item.command
    ns.target = target
    ns.isEnabled = item.enabled
    ns.image = image(item.symbol)
    switch item.mark {
    case .none: break
    case .off: ns.state = .off
    case .on: ns.state = .on
    case .mixed: ns.state = .mixed
    }
    if let shortcut = item.shortcut {
      switch shortcut.key {
      case .character(let c): ns.keyEquivalent = String(c)
      case .delete: ns.keyEquivalent = String(UnicodeScalar(NSBackspaceCharacter)!)
      }
      var modifiers: NSEvent.ModifierFlags = [.command]
      if shortcut.shift { modifiers.insert(.shift) }
      if shortcut.option { modifiers.insert(.option) }
      ns.keyEquivalentModifierMask = modifiers
    }
    return ns
  }

  private static func image(_ symbol: String?) -> NSImage? {
    symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
  }
}
