#if DEBUG
  import AppKit
  import SwiftUI
  import UmbraAPI
  import UmbraKit

  /// Pictures of the torrent menu's contents. The real menus are AppKit and
  /// SwiftUI menus, which can't be drawn offscreen, so these list what
  /// the shared description says (title, symbol, shortcut, tick, dimmed) for
  /// one selected torrent, several, none and no connection. The toolbar
  /// can't be drawn offscreen either. The Remove alert is drawn from its
  /// own content (the real alert, built as the app builds it, but never
  /// shown), so its words and buttons can be checked; its wording is also
  /// tested.
  @MainActor
  enum ActionSnapshots {
    static var entries: [SnapshotEntry] {
      [
        entry("menu-one-selected", note: "One torrent selected") { model in
          model.selection = [model.visibleRows[1].id]
          return model.torrentMenu(connected: true)
        },
        entry("menu-several-selected", note: "Several selected, categories and tags mixed") {
          model in
          // Rows chosen so their categories and tags differ (mixed ticks).
          model.selection = Set(model.visibleRows.prefix(6).map(\.id))
          return model.torrentMenu(connected: true)
        },
        entry("menu-none-selected", note: "Nothing selected") { model in
          model.torrentMenu(connected: true)
        },
        entry("menu-not-connected", note: "One selected, Umbra not connected") { model in
          model.selection = [model.visibleRows[1].id]
          return model.torrentMenu(connected: false)
        },
        removeAlert("remove-alert-one", own: [false], ticked: false),
        removeAlert("remove-alert-one-ticked", own: [false], ticked: true),
        removeAlert("remove-alert-own-files", own: [true], ticked: false),
        removeAlert("remove-alert-own-files-ticked", own: [true], ticked: true),
        removeAlert("remove-alert-some-own-ticked", own: [true, false, true], ticked: true),
      ]
    }

    /// The Remove alert for the stress list's first torrents; `own` says
    /// which were made from the person's own files, `ticked` whether the
    /// delete box is ticked.
    private static func removeAlert(_ name: String, own: [Bool], ticked: Bool) -> SnapshotEntry {
      SnapshotEntry(name: name, size: CGSize(width: 300, height: 470)) {
        let rows = zip(Fixtures.feed().torrents, own).map { torrent, mine in
          var t = torrent
          t.madeFromOwnFiles = mine ? true : nil
          return TorrentRow(t, now: Fixtures.now)
        }
        let prompt = ActionPrompts.RemovalAlert(RemoveConfirmation(TorrentSelection(rows))!)
        if ticked {
          prompt.box.state = .on
          prompt.changed(prompt.box)
        }
        prompt.alert.layout()
        return AnyView(AlertContent(prompt: prompt).frame(maxHeight: .infinity, alignment: .top))
      }
    }

    private static func entry(
      _ name: String, note: String, menu: @escaping @MainActor (MainWindowModel) -> TorrentMenu
    ) -> SnapshotEntry {
      SnapshotEntry(name: name, size: CGSize(width: 560, height: 800)) {
        let model = Fixtures.model()
        model.definedCategories = ["books", "datasets", "linux-isos", "movies"]
        return AnyView(MenuDescriptionView(note: note, menu: menu(model)))
      }
    }
  }

  /// The Remove alert, drawn by its own (never shown) window into a
  /// picture, in the picture's light or dark. Its text doesn't draw when
  /// its views are moved into another window, so it is drawn where it is.
  private struct AlertContent: NSViewRepresentable {
    let prompt: ActionPrompts.RemovalAlert

    func makeNSView(context: Context) -> NSImageView {
      let window = prompt.alert.window
      window.appearance = NSAppearance(
        named: context.environment.colorScheme == .dark ? .darkAqua : .aqua)
      prompt.alert.layout()
      let view = window.contentView?.superview ?? window.contentView ?? NSView()
      for _ in 0..<3 {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
      }
      let bounds = view.bounds
      let image = NSImage(size: bounds.size)
      if let rep = view.bitmapImageRepForCachingDisplay(in: bounds) {
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        image.addRepresentation(rep)
      }
      let imageView = NSImageView(image: image)
      imageView.frame = NSRect(origin: .zero, size: bounds.size)
      return imageView
    }

    func updateNSView(_ view: NSImageView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context)
      -> CGSize?
    {
      nsView.image?.size
    }
  }

  /// Lists a menu description's entries (the menu bar's version, which
  /// is the right-click menu plus Slow Mode), submenus drawn beneath
  /// their titles.
  private struct MenuDescriptionView: View {
    let note: String
    let menu: TorrentMenu

    var body: some View {
      VStack(alignment: .leading, spacing: 2) {
        Text("\(TorrentMenu.title) menu: \(note)").font(.headline).padding(.bottom, 6)
        lines(menu.menuBarEntries, indent: 0)
        Spacer(minLength: 0)
      }
      .padding(16)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func lines(_ entries: [TorrentMenuEntry], indent: Int) -> AnyView {
      AnyView(
        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
          switch entry {
          case .separator:
            Divider().padding(.vertical, 2)
          case .item(let item):
            row(
              title: item.title, symbol: item.symbol, shortcut: item.shortcut?.display,
              mark: item.mark, enabled: item.enabled, indent: indent)
          case .submenu(let title, let symbol, let enabled, let sub):
            row(
              title: title + "  ▸", symbol: symbol, shortcut: nil, mark: nil, enabled: enabled,
              indent: indent)
            lines(sub, indent: indent + 1)
          }
        })
    }

    private func row(
      title: String, symbol: String?, shortcut: String?, mark: MenuMark?, enabled: Bool,
      indent: Int
    ) -> some View {
      HStack(spacing: 6) {
        Text(tick(mark)).frame(width: 14)
        Image(systemName: symbol ?? "circle").opacity(symbol == nil ? 0 : 1).frame(width: 18)
        Text(title)
        Spacer()
        if let shortcut { Text(shortcut).foregroundStyle(.secondary) }
      }
      .padding(.leading, CGFloat(indent) * 28)
      .foregroundStyle(enabled ? .primary : .tertiary)
    }

    private func tick(_ mark: MenuMark?) -> String {
      switch mark {
      case .on: "✓"
      case .mixed: "–"
      case .off, .none: ""
      }
    }
  }
#endif
