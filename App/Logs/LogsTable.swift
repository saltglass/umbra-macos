import AppKit
import SwiftUI
import UmbraKit

/// The log lines as AppKit's table, shown in SwiftUI.
///
/// AppKit, not SwiftUI's `Table`: the table must stay scrolled to the end
/// while lines arrive, and must notice when the person scrolls away, and
/// SwiftUI's table can do neither. `LogsTableController` does the work;
/// this passes values in and the person's choices out.
struct LogsTable: NSViewRepresentable {
  var lines: [LogLine]
  /// Keep the end of the list in view.
  var following: Bool
  /// Where AppKit remembers the columns; nil for pictures.
  var autosaveName: String? = "LogsTable"
  /// The person scrolled; true if they stopped at the end.
  var onScroll: (Bool) -> Void
  /// The text to copy for these lines.
  var copyText: (Set<Int64>) -> String

  func makeCoordinator() -> LogsTableController {
    LogsTableController(autosaveName: autosaveName)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let controller = context.coordinator
    controller.owner = self
    controller.update(lines: lines, following: following)
    return controller.scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    let controller = context.coordinator
    controller.owner = self
    controller.update(lines: lines, following: following)
  }
}

/// The table, with ⌘C copying the selected lines as plain text.
final class LogsTableView: NSTableView {
  /// The text for the selected lines' numbers.
  var copyText: ((Set<Int64>) -> String)?
  /// The numbers of the lines in these rows.
  var idsForRows: ((IndexSet) -> Set<Int64>)?

  @objc func copy(_ sender: Any?) {
    guard let ids = idsForRows?(selectedRowIndexes), !ids.isEmpty,
      let text = copyText?(ids)
    else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    if item.action == #selector(copy(_:)) { return !selectedRowIndexes.isEmpty }
    return super.validateUserInterfaceItem(item)
  }
}

/// Runs the log table: cells, appending lines gently, following the end.
@MainActor
final class LogsTableController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
  let table = LogsTableView()
  let scrollView = NSScrollView()
  var owner: LogsTable?

  private(set) var lines: [LogLine] = []
  private var following = true
  /// True while this controller moves the table, so its own scrolling
  /// isn't taken for the person's.
  private var movingByCode = false

  private enum Column: String, CaseIterable {
    case time, level, source, message

    var title: String {
      switch self {
      case .time: "Time"
      case .level: "Level"
      case .source: "Source"
      case .message: "Message"
      }
    }
    var width: CGFloat {
      switch self {
      case .time: 76
      case .level: 70
      case .source: 140
      case .message: 420
      }
    }
    var minimumWidth: CGFloat {
      switch self {
      case .time: 60
      case .level: 54
      case .source: 60
      case .message: 160
      }
    }
  }

  init(autosaveName: String?) {
    super.init()
    table.style = .inset
    table.usesAlternatingRowBackgroundColors = true
    table.allowsMultipleSelection = true
    table.allowsEmptySelection = true
    table.allowsColumnReordering = false
    table.allowsColumnResizing = true
    table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    table.dataSource = self
    table.delegate = self
    for column in Column.allCases {
      let tableColumn = NSTableColumn(identifier: .init(column.rawValue))
      tableColumn.title = column.title
      tableColumn.width = column.width
      tableColumn.minWidth = column.minimumWidth
      tableColumn.resizingMask =
        column == .message ? [.autoresizingMask, .userResizingMask] : .userResizingMask
      table.addTableColumn(tableColumn)
    }
    if let autosaveName {
      table.autosaveName = autosaveName
      table.autosaveTableColumns = true
    }
    table.idsForRows = { [weak self] rows in
      guard let self else { return [] }
      return Set(rows.compactMap { $0 < self.lines.count ? self.lines[$0].id : nil })
    }
    table.copyText = { [weak self] ids in self?.owner?.copyText(ids) ?? "" }

    scrollView.documentView = table
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.borderType = .noBorder
    // Only the person's own scrolling (wheel, trackpad, dragging the
    // scroller) pauses or resumes following.
    NotificationCenter.default.addObserver(
      self, selector: #selector(personScrolled), name: NSScrollView.didLiveScrollNotification,
      object: scrollView)
    NotificationCenter.default.addObserver(
      self, selector: #selector(personScrolled),
      name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
  }

  isolated deinit { NotificationCenter.default.removeObserver(self) }

  // MARK: Updating

  func update(lines newLines: [LogLine], following newFollowing: Bool) {
    let old = lines
    lines = newLines
    let turnedOn = newFollowing && !following
    following = newFollowing

    if old.map(\.id) != newLines.map(\.id) {
      if let appended = appendedRange(old: old, new: newLines) {
        movingByCode = true
        NSAnimationContext.runAnimationGroup { context in
          context.duration = 0
          table.insertRows(at: IndexSet(appended), withAnimation: [])
        }
        movingByCode = false
      } else {
        let selected = Set(
          table.selectedRowIndexes.compactMap { $0 < old.count ? old[$0].id : nil })
        movingByCode = true
        table.reloadData()
        let rows = IndexSet(newLines.indices.filter { selected.contains(newLines[$0].id) })
        table.selectRowIndexes(rows, byExtendingSelection: false)
        movingByCode = false
      }
    }
    if following && (turnedOn || old.last?.id != newLines.last?.id) { scrollToEnd() }
  }

  /// The rows added at the end, if that is all that changed.
  private func appendedRange(old: [LogLine], new: [LogLine]) -> Range<Int>? {
    guard !old.isEmpty, new.count > old.count, new.first?.id == old.first?.id,
      new[old.count - 1].id == old[old.count - 1].id
    else { return nil }
    return old.count..<new.count
  }

  private func scrollToEnd() {
    guard !lines.isEmpty else { return }
    movingByCode = true
    table.scrollRowToVisible(lines.count - 1)
    movingByCode = false
  }

  @objc private func personScrolled(_ note: Notification) {
    guard !movingByCode else { return }
    let visible = scrollView.documentVisibleRect
    let atEnd = visible.maxY >= table.bounds.maxY - 2
    owner?.onScroll(atEnd)
  }

  // MARK: Data and cells

  func numberOfRows(in tableView: NSTableView) -> Int { lines.count }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
    -> NSView?
  {
    guard row < lines.count, let tableColumn,
      let column = Column(rawValue: tableColumn.identifier.rawValue)
    else { return nil }
    let cell =
      tableView.makeView(withIdentifier: LogCell.identifier, owner: nil) as? LogCell ?? LogCell()
    cell.show(lines[row], column: column.rawValue)
    return cell
  }
}

/// One cell: a single line of text.
final class LogCell: NSTableCellView {
  static let identifier = NSUserInterfaceItemIdentifier("LogCell")
  private let label = NSTextField(labelWithString: "")

  init() {
    super.init(frame: .zero)
    identifier = Self.identifier
    label.lineBreakMode = .byTruncatingTail
    label.maximumNumberOfLines = 1
    label.cell?.usesSingleLineMode = true
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    textField = label
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) { fatalError("not used") }

  func show(_ line: LogLine, column: String) {
    let size = NSFont.systemFontSize
    label.font = .systemFont(ofSize: size)
    label.textColor = .labelColor
    label.toolTip = nil
    switch column {
    case "time":
      label.stringValue = line.timeOfDay
      label.font = .monospacedDigitSystemFont(ofSize: size, weight: .regular)
      label.textColor = .secondaryLabelColor
    case "level":
      label.stringValue = line.level.title
      label.textColor = line.level.role.nsColor
    case "source":
      label.stringValue = line.source
      label.textColor = .secondaryLabelColor
    default:
      label.stringValue = line.text
      // The whole line, for text that is cut off.
      label.toolTip = line.plainText()
    }
  }
}
