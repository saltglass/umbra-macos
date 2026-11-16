#if DEBUG
  import AppKit
  import SwiftUI

  /// DEVELOPMENT ONLY: draws each view in `SnapshotRegistry` to a PNG, in
  /// light and dark, at 1x (one pixel per point, as on a 1080p screen), then
  /// quits. No window is shown and no helper is started.
  ///
  /// Views are drawn into an offscreen window with AppKit's own "cache
  /// display" drawing, not by capturing the screen (that needs a permission
  /// this Mac doesn't give command-line tools). `just snapshot` runs it.
  ///
  /// What it can't draw (found 2026-11-12, macOS 27): anything inside
  /// macOS's "Liquid Glass", which the window server puts together on
  /// screen. A `NavigationSplitView` sidebar comes out as an empty white
  /// panel, and toolbar buttons faint. Draw a sidebar's view as its own
  /// entry instead: a `List` in sidebar style draws fine on its own.
  /// Set `SNAPSHOT_DUMP=<entry name>` to print that entry's AppKit views.
  @MainActor
  enum SnapshotRunner {
    static func run(into folder: URL) -> Never {
      let app = NSApplication.shared
      // No Dock icon, no menu bar, never comes to the front.
      app.setActivationPolicy(.prohibited)
      app.finishLaunching()

      var problems = 0
      do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      } catch {
        print("Can't make \(folder.path): \(error.localizedDescription)")
        exit(1)
      }
      // SNAPSHOT_ONLY=<start of a name> draws just the matching pictures
      // (a full run takes many minutes).
      let only = ProcessInfo.processInfo.environment["SNAPSHOT_ONLY"]
      for entry in SnapshotRegistry.entries where only.map({ entry.name.hasPrefix($0) }) ?? true {
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
          let file = folder.appending(path: "\(entry.name)-\(suffix).png")
          let rep = render(entry, appearance: NSAppearance(named: appearance)!)
          let ink = Ink(rep)
          guard let png = rep.representation(using: .png, properties: [:]),
            (try? png.write(to: file)) != nil
          else {
            print("\(file.lastPathComponent): couldn't save")
            problems += 1
            continue
          }
          // A picture all in one or two colours means the view didn't draw.
          let blank = ink.colours <= 2
          if blank { problems += 1 }
          print(
            "\(file.lastPathComponent): \(rep.pixelsWide)x\(rep.pixelsHigh), "
              + "\(ink.colours) colours, \(Int((ink.fraction * 100).rounded()))% drawn"
              + (blank ? "  <- BLANK" : ""))
        }
      }
      exit(problems == 0 ? 0 : 1)
    }

    /// Draws one entry in one appearance.
    static func render(_ entry: SnapshotEntry, appearance: NSAppearance) -> NSBitmapImageRep {
      let frame = NSRect(origin: .zero, size: entry.size)
      let window = NSWindow(
        contentRect: frame,
        styleMask: entry.windowFrame
          ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView] : [.borderless],
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.appearance = appearance
      window.title = "Umbra"
      let hosting = NSHostingView(
        rootView: entry.makeView()
          .frame(width: entry.size.width, height: entry.size.height)
          .background(Color(nsColor: .windowBackgroundColor)))
      // Lets the view's .toolbar and title reach the window, as in the app.
      hosting.sceneBridgingOptions = [.toolbars, .title]
      hosting.frame = frame
      window.contentView = hosting

      // SwiftUI and AppKit's tables lay out over several turns of the run
      // loop; drawing too early can give empty tables. Give them a moment.
      for _ in 0..<6 {
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
      }
      window.displayIfNeeded()

      // With the window frame: the whole window (title bar and toolbar
      // included); otherwise just the view.
      let target: NSView = entry.windowFrame ? (hosting.superview ?? hosting) : hosting
      if ProcessInfo.processInfo.environment["SNAPSHOT_DUMP"] == entry.name { dump(target) }
      let bounds = target.bounds
      // One pixel per point, whatever the screen: the picture is made at 1x.
      let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(bounds.width), pixelsHigh: Int(bounds.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
      rep.size = bounds.size
      target.cacheDisplay(in: bounds, to: rep)
      window.close()
      return rep
    }

    /// Prints the AppKit views under `view`, for working out why something
    /// doesn't draw.
    static func dump(_ view: NSView, depth: Int = 0) {
      print(String(repeating: " ", count: depth) + "\(type(of: view)) \(view.frame)")
      for sub in view.subviews { dump(sub, depth: depth + 1) }
    }

    /// How much of a picture is drawn: the share of pixels that differ from
    /// its top-left corner, and how many different colours it has.
    struct Ink {
      let fraction: Double
      let colours: Int

      init(_ rep: NSBitmapImageRep) {
        let corner = rep.colorAt(x: 0, y: 0)
        var differing = 0
        var seen = Set<UInt32>()
        var total = 0
        // Every other pixel is plenty to tell.
        for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
          for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            guard let colour = rep.colorAt(x: x, y: y) else { continue }
            total += 1
            if colour != corner { differing += 1 }
            let r = UInt32(colour.redComponent * 255)
            let g = UInt32(colour.greenComponent * 255)
            let b = UInt32(colour.blueComponent * 255)
            seen.insert(r << 16 | g << 8 | b)
          }
        }
        fraction = total == 0 ? 0 : Double(differing) / Double(total)
        colours = seen.count
      }
    }
  }
#endif
