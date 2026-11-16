import AppKit
import UmbraKit

/// Runs the torrent list's AppKit table: gives it rows and cells, passes the
/// person's clicks back, and applies each second's update gently.
///
/// "Gently" means: only rows that came or went are inserted or removed,
/// only changed cells are refilled, the selection stays, and the rows on
/// screen stay where they are even when rows above them come or go.
@MainActor
final class TorrentTableController: NSObject, NSTableViewDataSource, NSTableViewDelegate,
  NSMenuDelegate
{
  let table = TorrentTableView()
  let scrollView = TorrentScrollView()

  /// What the table shows now.
  private(set) var rows: [TorrentRow] = []
  /// Nil until the first update, so the first one draws the sort indicator.
  private var sort: TorrentSort?
  private var resetKey = ""
  /// The latest closures from SwiftUI (see `TorrentTable`).
  var owner: TorrentTable?
  /// True while the controller itself changes the table, so AppKit's
  /// "selection changed" notices from that aren't taken as the person's.
  private var applying = false

  init(autosaveName: String?) {
    super.init()
    setUpTable(autosaveName: autosaveName)
  }

  // MARK: Setting up

  private func setUpTable(autosaveName: String?) {
    table.style = .inset
    table.usesAlternatingRowBackgroundColors = true
    table.allowsMultipleSelection = true
    table.allowsEmptySelection = true
    table.allowsColumnReordering = true
    table.allowsColumnResizing = true
    table.allowsTypeSelect = true
    table.rowSizeStyle = .default
    // A little less space between columns than AppKit's default, so nine
    // columns leave the name room in a normal-sized window.
    table.intercellSpacing = NSSize(width: 10, height: table.intercellSpacing.height)
    // Only the Name column takes up spare width when the window is resized.
    table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    table.dataSource = self
    table.delegate = self
    table.target = self
    table.doubleAction = #selector(doubleClicked)

    for column in TorrentColumn.macColumnOrder {
      let tableColumn = NSTableColumn(identifier: .init(column.rawValue))
      tableColumn.title = column.header
      tableColumn.headerCell.alignment = column.alignsRight ? .right : .natural
      tableColumn.width = column.defaultWidth
      tableColumn.minWidth = column.minimumWidth
      tableColumn.resizingMask =
        column == .name ? [.autoresizingMask, .userResizingMask] : .userResizingMask
      tableColumn.isHidden = !TorrentColumn.macDefaultColumns.contains(column)
      tableColumn.headerToolTip = column.menuLabel
      table.addTableColumn(tableColumn)
    }

    // Right-click on the header: tick the columns to show.
    let columnsMenu = NSMenu(title: "Columns")
    columnsMenu.delegate = self
    table.headerView?.menu = columnsMenu

    // Set last: AppKit then restores the person's own column order, widths
    // and hidden columns from earlier launches, and saves their changes.
    if let autosaveName {
      table.autosaveName = autosaveName
      table.autosaveTableColumns = true
    }

    scrollView.documentView = table
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.borderType = .noBorder

    table.rowMenu = { [weak self] in
      guard let self, let owner = self.owner else { return nil }
      return owner.menuProvider?(self.selectedHashes())
    }
    table.keyCommand = { [weak self] key in
      guard let self, let owner = self.owner, let handle = owner.onKeyCommand else { return false }
      return handle(key, self.selectedHashes())
    }
  }

  // MARK: Updating

  /// Shows `newRows`, `selection` and `newSort`. `newResetKey` changes
  /// when the filter or search changes: then the list starts from the top.
  func update(
    rows newRows: [TorrentRow], selection: Set<String>, sort newSort: TorrentSort,
    resetKey newResetKey: String
  ) {
    applying = true
    defer { applying = false }

    let resorted = sort != nil && newSort != sort
    if newSort != sort {
      sort = newSort
      showSortIndicator(newSort)
    }
    let reset = newResetKey != resetKey || rows.isEmpty
    resetKey = newResetKey

    if newRows != rows {
      let old = rows
      rows = newRows
      if reset {
        // A new filter or search: start from the top.
        table.reloadData()
        table.scrollRowToVisible(0)
      } else if resorted {
        // The person asked for a new order: redraw, then show the selection.
        table.reloadData()
        select(selection, scrollIntoView: true)
        return
      } else {
        // A live update: change only what changed, keeping the place.
        let anchor = captureAnchor()
        if let steps = ListStep.steps(from: old.map(\.id), to: newRows.map(\.id)) {
          apply(steps)
          refillChangedCells(old: old)
        } else {
          table.reloadData()  // so much moved that redrawing is quicker
        }
        restore(anchor, old: old)
      }
    }
    select(selection, scrollIntoView: false)
  }

  /// Applies the row changes without animation: rows sliding about every
  /// second would be distracting.
  private func apply(_ steps: [ListStep]) {
    guard !steps.isEmpty else { return }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0
      context.allowsImplicitAnimation = false
      table.beginUpdates()
      for step in steps {
        switch step {
        case .remove(let indexes): table.removeRows(at: indexes, withAnimation: [])
        case .insert(let index): table.insertRows(at: IndexSet(integer: index), withAnimation: [])
        case .move(let from, let to): table.moveRow(at: from, to: to)
        }
      }
      table.endUpdates()
    }
  }

  /// Refills the cells on screen whose row changed; cells off screen are
  /// filled when they scroll into view.
  private func refillChangedCells(old: [TorrentRow]) {
    let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let visible = table.rows(in: table.visibleRect)
    guard visible.length > 0 else { return }
    for index in visible.location..<min(visible.location + visible.length, rows.count) {
      let row = rows[index]
      guard before[row.id] != row else { continue }
      for (columnIndex, column) in table.tableColumns.enumerated() where !column.isHidden {
        guard let cell = table.view(atColumn: columnIndex, row: index, makeIfNecessary: false),
          let id = TorrentColumn(rawValue: column.identifier.rawValue)
        else { continue }
        fill(cell, column: id, row: row)
      }
    }
  }

  /// Where the view was: its top row, and how far that row was cut off.
  private struct Anchor {
    let top: Int
    let offset: CGFloat
  }

  private func captureAnchor() -> Anchor {
    let top = max(table.rows(in: table.visibleRect).location, 0)
    let offset = top < table.numberOfRows ? table.rect(ofRow: top).minY - table.visibleRect.minY : 0
    return Anchor(top: top, offset: offset)
  }

  /// Scrolls so the same rows are on screen as before the update (see
  /// `ListStep.topRow` for which row that is).
  private func restore(_ anchor: Anchor, old: [TorrentRow]) {
    guard
      let target = ListStep.topRow(old: old.map(\.id), new: rows.map(\.id), top: anchor.top)
    else { return }
    let y = table.rect(ofRow: target).minY - anchor.offset
    guard abs(y - table.visibleRect.minY) > 0.5 else { return }
    table.scroll(NSPoint(x: table.visibleRect.minX, y: y))
    scrollView.reflectScrolledClipView(scrollView.contentView)
  }

  /// Makes the table's selection match `selection`.
  func select(_ selection: Set<String>, scrollIntoView: Bool) {
    let wanted = IndexSet(rows.indices.filter { selection.contains(rows[$0].id) })
    if wanted != table.selectedRowIndexes {
      table.selectRowIndexes(wanted, byExtendingSelection: false)
    }
    if scrollIntoView, let first = wanted.first { table.scrollRowToVisible(first) }
  }

  private func selectedHashes() -> Set<String> {
    Set(table.selectedRowIndexes.compactMap { $0 < rows.count ? rows[$0].id : nil })
  }

  // MARK: Sorting

  private func showSortIndicator(_ sort: TorrentSort) {
    for column in table.tableColumns {
      let isSorted = column.identifier.rawValue == sort.column.rawValue
      table.setIndicatorImage(
        isSorted
          ? NSImage(
            named: sort.descending ? "NSDescendingSortIndicator" : "NSAscendingSortIndicator")
          : nil,
        in: column)
    }
    table.highlightedTableColumn = table.tableColumns.first {
      $0.identifier.rawValue == sort.column.rawValue
    }
  }

  func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
    guard let column = TorrentColumn(rawValue: tableColumn.identifier.rawValue) else { return }
    // The same column turns round; another starts its own way (numbers high to low).
    owner?.onSort((sort ?? .default).clicked(column))
  }

  // MARK: Data source and cells

  func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    guard let tableColumn, row < rows.count,
      let column = TorrentColumn(rawValue: tableColumn.identifier.rawValue)
    else { return nil }
    let cell = makeCell(for: column)
    fill(cell, column: column, row: rows[row])
    return cell
  }

  private func makeCell(for column: TorrentColumn) -> NSView {
    switch column {
    case .progress:
      return table.makeView(withIdentifier: ProgressCell.identifier, owner: nil) ?? ProgressCell()
    case .status:
      return table.makeView(withIdentifier: StatusCell.identifier, owner: nil) ?? StatusCell()
    default:
      // Left- and right-aligned text cells are kept apart for reuse.
      let id = NSUserInterfaceItemIdentifier(column.alignsRight ? "TextRight" : "TextLeft")
      if let cell = table.makeView(withIdentifier: id, owner: nil) { return cell }
      let cell = TextCell(alignsRight: column.alignsRight)
      cell.identifier = id
      return cell
    }
  }

  private func fill(_ cell: NSView, column: TorrentColumn, row: TorrentRow) {
    switch cell {
    case let cell as ProgressCell: cell.show(row)
    case let cell as StatusCell: cell.show(row)
    case let cell as TextCell:
      let toolTip = column == .name ? (row.note.map { "\(row.name)\n\($0.text)" } ?? row.name) : nil
      cell.show(Self.text(column, row), toolTip: toolTip)
    default: break
    }
  }

  /// The words a plain column shows.
  static func text(_ column: TorrentColumn, _ row: TorrentRow) -> String {
    switch column {
    case .name: row.name
    case .size: row.sizeText
    case .progress: row.progressText
    case .status: row.statusLabel
    case .downSpeed: row.downSpeedText
    case .upSpeed: row.upSpeedText
    case .eta: row.etaText
    case .ratio: row.ratioText
    case .category: row.categoryText
    case .tags: row.tags.isEmpty ? Format.dash : row.tags.joined(separator: ", ")
    case .addedAt: row.addedText
    case .seeds: row.seedsText
    case .peers: row.peersText
    case .downloaded: row.downloadedText
    case .uploaded: row.uploadedText
    case .seedTime: row.seedTimeText
    case .tracker: row.trackerText
    case .savePath: row.savePath
    case .completedAt: row.completedText
    case .queuePosition: row.queueText
    }
  }

  /// Typing a name jumps to it; only the name counts.
  func tableView(
    _ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int
  )
    -> String?
  {
    guard tableColumn?.identifier.rawValue == TorrentColumn.name.rawValue, row < rows.count else {
      return nil
    }
    return rows[row].name
  }

  // MARK: The person's actions

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !applying else { return }
    owner?.onSelect(selectedHashes())
  }

  @objc private func doubleClicked() {
    let row = table.clickedRow
    guard row >= 0, row < rows.count else { return }
    owner?.onDoubleClick?(rows[row].id)
  }

  // MARK: The columns menu

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    for column in TorrentColumn.macColumnOrder {
      guard let tableColumn = table.tableColumn(withIdentifier: .init(column.rawValue)) else {
        continue
      }
      let item = NSMenuItem(
        title: column.menuLabel, action: column.canHide ? #selector(toggleColumn(_:)) : nil,
        keyEquivalent: "")
      item.target = self
      item.representedObject = tableColumn
      item.state = tableColumn.isHidden ? .off : .on
      menu.addItem(item)
    }
  }

  @objc private func toggleColumn(_ item: NSMenuItem) {
    guard let column = item.representedObject as? NSTableColumn else { return }
    column.isHidden.toggle()
  }
}
