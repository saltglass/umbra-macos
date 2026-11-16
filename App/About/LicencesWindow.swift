import AppKit
import SwiftUI

/// Where the licence text is: made by scripts/licenses.sh, copied into the
/// app at build time.
enum LicenceText {
  static func load() -> String {
    guard let file = Bundle.main.url(forResource: "THIRD-PARTY-LICENSES", withExtension: "txt"),
      let text = try? String(contentsOf: file, encoding: .utf8)
    else { return "The licence text is missing from this copy of the app." }
    return text
  }
}

/// The Licences… window: the third-party licences, scrollable and
/// selectable, in a monospaced font.
struct LicencesWindow: View {
  @State private var text = ""

  var body: some View {
    LicencesView(text: text)
      .frame(minWidth: 560, minHeight: 320)
      // Read when the window opens, not at launch: the file is large.
      .task { if text.isEmpty { text = LicenceText.load() } }
  }
}

/// A text view that only reads (the licence file is hundreds of kilobytes,
/// which AppKit's text view handles much better than SwiftUI's `Text`).
/// Uses the system's colours, so light and dark just work.
struct LicencesView: NSViewRepresentable {
  let text: String

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSTextView.scrollableTextView()
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = true
    scroll.backgroundColor = .textBackgroundColor
    let view = scroll.documentView as! NSTextView
    view.isEditable = false
    view.isSelectable = true
    view.isRichText = false
    view.usesFindBar = true
    view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    view.textColor = .labelColor
    view.textContainerInset = NSSize(width: 12, height: 12)
    view.setAccessibilityLabel("Third-party licences")
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    let view = scroll.documentView as! NSTextView
    if view.string != text { view.string = text }
  }
}
