import AppKit
import UmbraKit

// The torrent list's cells. Each is made once and then reused for
// whichever row scrolls into view; `show(_:)` fills it from a row.

/// Plain words: a name, a size, a date. Figures are right-aligned with
/// digits of equal width, so they line up down the column.
final class TextCell: NSTableCellView {
  static let identifier = NSUserInterfaceItemIdentifier("TextCell")
  private let label = NSTextField(labelWithString: "")

  init(alignsRight: Bool) {
    super.init(frame: .zero)
    identifier = Self.identifier
    label.lineBreakMode = .byTruncatingTail
    label.alignment = alignsRight ? .right : .natural
    label.font =
      alignsRight
      ? .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
      : .systemFont(ofSize: NSFont.systemFontSize)
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

  func show(_ text: String, toolTip: String? = nil) {
    if label.stringValue != text { label.stringValue = text }
    label.toolTip = toolTip
  }
}

/// A thin system progress bar with the percentage beside it.
final class ProgressCell: NSTableCellView {
  static let identifier = NSUserInterfaceItemIdentifier("ProgressCell")
  private let bar = NSProgressIndicator()
  private let label = NSTextField(labelWithString: "")

  override init(frame: NSRect) {
    super.init(frame: frame)
    identifier = Self.identifier
    bar.style = .bar
    bar.isIndeterminate = false
    bar.controlSize = .small
    bar.minValue = 0
    bar.maxValue = 1
    label.alignment = .right
    label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    textField = label
    for view in [bar, label] as [NSView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    NSLayoutConstraint.activate([
      bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
      bar.centerYAnchor.constraint(equalTo: centerYAnchor),
      label.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 6),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
      // Room for "100%" in the system font.
      label.widthAnchor.constraint(equalToConstant: 36),
    ])
  }

  required init?(coder: NSCoder) { fatalError("not used") }

  func show(_ row: TorrentRow) {
    if bar.doubleValue != row.barValue { bar.doubleValue = row.barValue }
    if label.stringValue != row.progressText { label.stringValue = row.progressText }
  }
}

/// What a torrent is doing: an SF Symbol and the words, in the status's
/// system colour. On a selected row both turn the selection's text colour,
/// so they stay readable on the highlight (as Finder's tags do).
final class StatusCell: NSTableCellView {
  static let identifier = NSUserInterfaceItemIdentifier("StatusCell")
  private let icon = NSImageView()
  private let label = NSTextField(labelWithString: "")
  private var role: ColorRole = .secondary

  override init(frame: NSRect) {
    super.init(frame: frame)
    identifier = Self.identifier
    icon.symbolConfiguration = .init(pointSize: NSFont.systemFontSize, weight: .regular)
    icon.setContentHuggingPriority(.required, for: .horizontal)
    label.lineBreakMode = .byTruncatingTail
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    for view in [icon, label] as [NSView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    NSLayoutConstraint.activate([
      icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
      icon.centerYAnchor.constraint(equalTo: centerYAnchor),
      icon.widthAnchor.constraint(equalToConstant: 16),
      label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
      label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) { fatalError("not used") }

  func show(_ row: TorrentRow) {
    if label.stringValue != row.statusLabel {
      label.stringValue = row.statusLabel
      icon.image = NSImage(systemSymbolName: row.kind.symbolName, accessibilityDescription: nil)
    }
    // Umbra's own words for what went wrong, on hover.
    toolTip = row.note?.text ?? row.error
    role = row.kind.textRole
    applyColour()
  }

  override var backgroundStyle: NSView.BackgroundStyle {
    didSet { applyColour() }
  }

  private func applyColour() {
    let colour: NSColor =
      backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : role.nsColor
    label.textColor = colour
    icon.contentTintColor = colour
  }
}
