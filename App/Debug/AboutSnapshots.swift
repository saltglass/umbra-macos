#if DEBUG
  import SwiftUI
  import UmbraKit

  /// Pictures of the About window (with a known server version, and with
  /// the server not running) and of the Licences window with a short
  /// sample text. All made up.
  @MainActor
  enum AboutSnapshots {
    private static let info = AboutInfo(name: "Umbra", version: "0.1.1", build: "7")

    static var entries: [SnapshotEntry] {
      [
        SnapshotEntry(name: "about", size: CGSize(width: 400, height: 320)) {
          AnyView(
            AboutView(
              info: info,
              serverLine: AboutInfo.serverLine(phase: .running, version: "v0.4.0"),
              onSourceCode: {}, onLicences: {}))
        },
        SnapshotEntry(name: "about-server-not-running", size: CGSize(width: 400, height: 320)) {
          AnyView(
            AboutView(
              info: info,
              serverLine: AboutInfo.serverLine(phase: .starting, version: nil),
              onSourceCode: {}, onLicences: {}))
        },
        SnapshotEntry(name: "licences", size: CGSize(width: 640, height: 400), windowFrame: true) {
          AnyView(LicencesView(text: sampleLicences))
        },
      ]
    }

    private static let sampleLicences = """
      THIRD-PARTY LICENCES

      Umbra for macOS is free software under the GNU General Public License,
      version 3.

      ================================================================================
      example-module 1.2.3
      --------------------------------------------------------------------------------

      [LICENSE]

      MIT License

      Copyright (c) 2026 The Example Authors

      Permission is hereby granted, free of charge, to any person obtaining a copy
      of this software and associated documentation files (the "Software"), to deal
      in the Software without restriction, including without limitation the rights
      to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
      copies of the Software, and to permit persons to whom the Software is
      furnished to do so, subject to the following conditions:

      The above copyright notice and this permission notice shall be included in all
      copies or substantial portions of the Software.
      """
  }
#endif
