import AppKit
import SwiftUI
import UmbraKit

extension ColorRole {
  /// The system colour for this role: it follows light and dark, and the
  /// person's own accent colour.
  var color: Color {
    switch self {
    case .accent: .accentColor
    case .green: .green
    case .orange: .orange
    case .red: .red
    case .secondary: .secondary
    }
  }

  /// The same, for AppKit views (the torrent list).
  var nsColor: NSColor {
    switch self {
    case .accent: .controlAccentColor
    case .green: .systemGreen
    case .orange: .systemOrange
    case .red: .systemRed
    case .secondary: .secondaryLabelColor
    }
  }
}
