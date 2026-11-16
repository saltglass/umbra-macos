#!/usr/bin/env swift
// Makes the app's icons: App/Assets.xcassets/AppIcon.appiconset (the real
// one) and AppIconDev.appiconset (the development build's, with a "DEV"
// band so the two are never mixed up in the Dock).
//
// Run it with `just icon`, or `swift scripts/make-icon.swift`, from the
// project folder. It needs nothing but what macOS already has, and it
// draws the same pictures every time. The pictures it makes are committed,
// so an ordinary build never needs to run it: run it only after changing
// Config/icon/umbra-icon.svg or the design below.
//
// The design follows macOS's icon grid: a 1024-point canvas whose middle
// 824 x 824 holds a rounded square (the "tile") and whose edge is left
// clear, so the system can add its own shadow. The tile is near-black and
// carries the Umbra mark (a shield with an eclipse) in the middle.

import AppKit
import CoreGraphics
import Foundation

// MARK: The design (all measured on the 1024-point canvas)

let canvas: CGFloat = 1024
let tileSize: CGFloat = 824
let cornerRadius: CGFloat = 185
/// The mark's height as a share of the tile's.
let markShare: CGFloat = 0.60

/// Near-black, with a very faint lift toward the top.
let tileTop = CGColor(srgbRed: 0x12 / 255, green: 0x10 / 255, blue: 0x1b / 255, alpha: 1)
let tileBottom = CGColor(srgbRed: 0x07 / 255, green: 0x06 / 255, blue: 0x0b / 255, alpha: 1)

/// The development build's band: how tall it is (share of the tile), its
/// colour and its text colour.
let bandShare: CGFloat = 0.24
let bandColour = CGColor(srgbRed: 1.0, green: 0.62, blue: 0.04, alpha: 1)
let bandTextColour = CGColor(srgbRed: 0.07, green: 0.05, blue: 0.02, alpha: 1)

// The SVG's own drawing space and the part of it the shield fills.
let svgBox = CGRect(x: 30, y: 15, width: 196, height: 230)

// MARK: Reading the mark

let root = URL(filePath: CommandLine.arguments[0]).deletingLastPathComponent()
  .deletingLastPathComponent()
let here = URL(filePath: FileManager.default.currentDirectoryPath)
let projectFolder =
  FileManager.default.fileExists(atPath: here.appending(path: "Config/icon").path) ? here : root
let svgFile = projectFolder.appending(path: "Config/icon/umbra-icon.svg")

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("make-icon: \(message)\n".utf8))
  exit(1)
}

/// The mark. Its colours are written as CSS variables with a fallback
/// (`var(--umbra-violet, #9851fb)`); macOS's SVG reader may not know
/// those, so each one is replaced by its fallback colour first.
func loadMark() -> NSImage {
  guard var text = try? String(contentsOf: svgFile, encoding: .utf8) else {
    fail("can't read \(svgFile.path)")
  }
  let variable = try! NSRegularExpression(pattern: #"var\(--[a-z-]+,\s*(#[0-9a-fA-F]{6})\)"#)
  text = variable.stringByReplacingMatches(
    in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1")
  guard let image = NSImage(data: Data(text.utf8)), image.size.width > 0 else {
    fail("macOS couldn't read \(svgFile.path) as an SVG picture")
  }
  return image
}

// MARK: Drawing one icon

/// Draws the whole 1024-point canvas, scaled to `pixels` across.
func draw(pixels: Int, dev: Bool, mark: NSImage) -> Data {
  let space = CGColorSpace(name: CGColorSpace.sRGB)!
  guard
    let context = CGContext(
      data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { fail("can't make a \(pixels)-pixel picture") }
  context.interpolationQuality = .high
  context.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)

  let margin = (canvas - tileSize) / 2
  let tile = CGRect(x: margin, y: margin, width: tileSize, height: tileSize)
  let shape = CGPath(
    roundedRect: tile, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

  context.saveGState()
  context.addPath(shape)
  context.clip()

  // The tile. (The origin is the bottom left, so "top" is the larger y.)
  let gradient = CGGradient(
    colorsSpace: space, colors: [tileBottom, tileTop] as CFArray, locations: [0, 1])!
  context.drawLinearGradient(
    gradient, start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: tile.maxY), options: [])

  // The mark, centred on the tile. The shield (not the SVG's whole box)
  // is what is measured and centred.
  // In the development icon the mark is a little smaller and sits in the
  // part of the tile above the band, so the band doesn't cut into it.
  let bandHeight = tileSize * bandShare
  let share = dev ? markShare * 0.92 : markShare
  let scale = tileSize * share / svgBox.height
  let markWidth = mark.size.width * scale
  let markHeight = mark.size.height * scale
  let centre = CGPoint(x: tile.midX, y: dev ? tile.midY + bandHeight / 2 : tile.midY)
  // The SVG's y runs downward; flip to find where its box centre lands.
  let boxCentreFromLeft = (svgBox.midX / mark.size.width) * markWidth
  let boxCentreFromTop = (svgBox.midY / mark.size.height) * markHeight
  let markRect = CGRect(
    x: centre.x - boxCentreFromLeft, y: centre.y - (markHeight - boxCentreFromTop),
    width: markWidth, height: markHeight)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
  mark.draw(in: markRect, from: .zero, operation: .sourceOver, fraction: 1)
  NSGraphicsContext.restoreGraphicsState()

  if dev {
    let band = CGRect(x: tile.minX, y: tile.minY, width: tileSize, height: bandHeight)
    context.setFillColor(bandColour)
    context.fill(band)
    let font = NSFont.systemFont(ofSize: band.height * 0.62, weight: .black)
    let words = NSAttributedString(
      string: "DEV",
      attributes: [
        .font: font, .kern: band.height * 0.06,
        .foregroundColor: NSColor(cgColor: bandTextColour)!,
      ])
    let size = words.size()
    // Centred by the capital letters' height, not the line's: the text is
    // drawn from the bottom of its line, which sits below the baseline by
    // the font's (negative) descender.
    let origin = CGPoint(
      x: band.midX - size.width / 2, y: band.midY - font.capHeight / 2 + font.descender)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    words.draw(at: origin)
    NSGraphicsContext.restoreGraphicsState()
  }
  context.restoreGState()

  guard let image = context.makeImage() else { fail("can't finish a \(pixels)-pixel picture") }
  let rep = NSBitmapImageRep(cgImage: image)
  guard let png = rep.representation(using: .png, properties: [:]) else {
    fail("can't make a PNG")
  }
  return png
}

// MARK: Writing the asset catalogue

/// Every size macOS wants: (points, scale).
let sizes: [(points: Int, scale: Int)] = [
  (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

func json(_ object: Any) -> Data {
  try! JSONSerialization.data(
    withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
}

let catalogue = projectFolder.appending(path: "App/Assets.xcassets")
let mark = loadMark()
let fileManager = FileManager.default

for (name, dev) in [("AppIcon", false), ("AppIconDev", true)] {
  let folder = catalogue.appending(path: "\(name).appiconset")
  try? fileManager.removeItem(at: folder)
  try! fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
  var images: [[String: String]] = []
  for (points, scale) in sizes {
    let file = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try! draw(pixels: points * scale, dev: dev, mark: mark).write(to: folder.appending(path: file))
    images.append([
      "filename": file, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)",
    ])
  }
  let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
  try! json(contents).write(to: folder.appending(path: "Contents.json"))
  print("Made \(folder.path)")
}
try! json(["info": ["author": "xcode", "version": 1]])
  .write(to: catalogue.appending(path: "Contents.json"))
