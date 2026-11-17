# Changelog

What changed in each version of Umbra for macOS, newest first.

## 0.1.2 (2026-11-17)

- **Umbra 0.4.0 inside**, the released version (0.1.1 carried the last
  development version before it; nothing about how it behaves differs).
  About now shows "Umbra server 0.4.0".
- **About has "Source Code" again**, which opens this app's own source
  on GitHub.
- **The inspector runs the full height of the window.** The list's
  buttons and the VPN pill now stop at its edge instead of sitting
  above it. The search field stays at the window's right-hand edge
  (where macOS puts it).

## 0.1.1 (2026-11-15)

The first release.

Umbra for macOS is a native Mac app for Umbra, the BitTorrent client. The
Umbra server is built into the app and answers only this Mac: nothing
listens on your network.

- **Main window** with the list of torrents, a sidebar and an inspector for
  the one you pick.
- **Settings**, including saved VPNs.
- **Nothing goes out before a VPN is set up.** Every torrent is held until
  you add a VPN or choose "Start without VPN".
- **Opens `.torrent` files and magnet links.**
- **Menu bar item**, so torrents carry on when the window is closed.
- **Notifications.**
- **Keep awake**, so the Mac doesn't sleep while it is downloading.
- **Open at login.**
- **Move** a torrent's files, **speed limits**, **create a torrent**, a
  **log** to read, and **backup and restore**.
