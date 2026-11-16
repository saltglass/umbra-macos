# Umbra for macOS: plan

Drafted 2026-11-12; decisions settled the same day (see CLAUDE.md).

**Size of the whole project: large.** About the same as Umbra's web UI
(its M2) plus a packaging layer Umbra never needed. Almost none of the cost
is engine work: it is a second interface over about 77 API operations, and
Mac signing and release.

## What it is

A native Mac app for Umbra: real windows, menus, sheets, a Settings window
and a menu bar item, in place of the web page. It is the same Umbra
underneath, so it does what the Docker version does.

## How it works

```
+--------------------------- Umbra.app ----------------------------+
|                                                                  |
|  The Mac interface (Swift)          The helper (Umbra, Go)       |
|  windows, menus, Settings,   <--->  engine, VPN, kill switch,    |
|  menu bar item, Finder              queue, limits, settings      |
|                                                                  |
|        /api/v1 and the live-update stream, on 127.0.0.1,         |
|        with a token made fresh at every launch                   |
+------------------------------------------------------------------+
```

- **The real Umbra server ships inside the app** and runs as a hidden
  helper. The engine, the VPN, the kill switch, queueing and limits are
  the same code as the Docker version. Nothing is ported or rewritten.
- **The Mac interface uses the same API as the web page.** Its Swift API
  code is generated from Umbra's `api/openapi.yaml`. When Umbra's API
  changes, the Mac app stops compiling until it catches up, so the two
  can't drift apart unnoticed.
- **The app pins one Umbra version** (`UMBRA_VERSION`). The helper and the
  API code are both built from that version.
- **The VPN needs nothing from macOS.** Umbra's WireGuard runs inside the
  helper: no system extension, no admin prompt, and the rest of the Mac's
  traffic is untouched. Only torrents go through the tunnel.
- **Private by default.** The helper answers only on this Mac (127.0.0.1),
  and only to the app that started it. Nothing is ever opened to the
  network: there is no web interface for other devices (Dan, 2026-11-14;
  Umbra in Docker is for that).

### Why this way

- *Rewriting the engine in Swift* would lose parity on day one and repeat
  every hard-won engine fix.
- *Building Umbra into the app as a library* needs a different kind of Go
  build than Umbra uses, and a crash in the engine would take the window
  down with it. As a helper, the app can restart it and say what happened.
- *Wrapping the web page in a window* isn't a native app.

## What parity means

Everything the engine can do is reachable from the Mac app. Three things
are deliberately different:

| On the web page | On the Mac |
|---|---|
| Save files to your computer | Show in Finder (the files are already here) |
| Settings → Appearance (accent, fonts, corners) | Follows the system: light, dark, accent colour |
| Sign-in, single sign-on, API key, app password, bypass list | Not there: the app is only ever used on this Mac |

Mac-only additions: opening `.torrent` files and magnet links, drag and
drop, Show in Finder, system notifications, the menu bar item, keeping the
Mac awake while downloading.

## Changes needed in Umbra itself (small)

Done in the `umbra` repo as the first part of M0. Each is off unless asked
for, so the Docker version behaves exactly as before.

- **Listen on a chosen address.** Today the server answers on every
  network interface. The helper must answer on 127.0.0.1 only, on a port
  it picks itself.
- **A launch token.** The app reaches its own helper without a sign-in
  screen by sending a random token made at launch. It works only on the
  private listener, is never stored, and is tested like every other way
  of signing in.
- **Stop when the app is gone.** If the app crashes, the helper shuts
  down cleanly instead of running on with no window.
- **Mac builds** of the Umbra binary.
- **Umbra's CLAUDE.md** lists "a desktop app" as a non-goal. That line
  changes to point here.

## Milestones

Each one ends usable and tested. Each gets its own plan in `docs/` and
Dan's OK before it starts.

### M0 · Foundation (medium) — done 2026-11-12
See docs/m0-plan.md. The Umbra changes above; this repo and its Xcode
project; starting, watching and stopping the helper; the generated API
code; the live feed.
*Done when:* the app opens and shows made-up torrents updating live, and
quitting it stops the helper cleanly.

### M1 · The main window (large) — done 2026-11-13
Boards 1 to 7 of the design canvas.
- Sidebar (status, categories, tags, trackers, with counts), the torrent
  list (sortable, resizable, chosen columns), toolbar,
  search, status bar.
- The inspector: General, Trackers, Peers, Files (choosing files and
  priorities).
- The VPN pill with the address peers see; the banner when the VPN is
  down or the disk is nearly full.
- The Add sheet (file, magnet, web address; category, tags, file picker),
  the Remove alert, the right-click menu, the Torrent menu, keyboard
  shortcuts. Dark and light.
- The list starts as a SwiftUI table. It is measured with 100 live
  torrents early in the milestone; if it's slow, it becomes an AppKit
  table before anything is built on top of it.
*Done when:* against the made-up swarm, Dan can do everything he does on
the web page's main screen. (Real day-to-day use waits for M2: the VPN is
set up in Settings.) See docs/m1-plan.md.

### M2 · Settings (medium) — done 2026-11-13
The Settings window, tied to Umbra's real settings: downloads (folders,
incomplete folder, watch folder, space kept free, categories), speed and
slow mode with its schedule, queue, seeding goals, connection, saved VPNs
with switching when one is down, email notifications. The design canvas
is corrected first (see below).
*Done when:* every setting on the web page can be changed here.

### M3 · Mac integration (medium)
`.torrent` files and magnet links open in Umbra; drag and drop; Show in
Finder; system notifications; the menu bar item (board 8); keep the Mac
awake while downloading; sleep and wake with the kill switch.
*Done when:* board 8 works, and a sleep and wake cycle never sends
anything outside the VPN.

### M4 · The rest of parity (medium) — done 2026-11-15
Create torrent; a torrent's and a category's limits; moving files; the
Logs window; backup and restore. No "Web interface for other devices"
(Dan, 2026-11-14: Umbra in Docker is for that).
*Done when:* nothing on the web page is missing, apart from the table
under "What parity means".

### M5 · Release (small) — done 2026-11-15
The app icon, About and the licences list, a version number, a disk
image (`just dist`), the README. **No signing by Apple and no download
page for now** (Dan, 2026-11-15: he expects to be the only user; the
$99 Apple Developer account waits until that changes). The source is
public on GitHub.
docs/m5-plan.md keeps the signed, public plan for then.
*Done when:* Dan's own copy is installed from the disk image.

### Later (designed for, not built)
- **Remote control:** the same window connected to an Umbra on another
  machine. The API code already takes an address and a credential, so
  this is mostly sign-in and hiding what only works locally (Show in
  Finder).
- Running with no app open (a login item).
- Intel Macs.
- Updating itself.

## The design canvas

The Claude Design canvas "Umbra for macOS" (nine boards, private to Dan)
is the visual spec. Its Settings board was drawn before this plan and
disagrees with Umbra in places. It is corrected before M2:

- **Comes out:** "Map port with UPnP" (Umbra never opens a port on the
  router), the Encryption choice and Disk cache (fixed defaults in
  Umbra), Local peer discovery, and "Send torrent traffic through wg0"
  (Umbra's tunnel is built in, not a system interface).
- **Goes in:** saved VPNs and switching when one is down, seeding goals,
  the watch folder, email notifications, Create torrent, the limits
  dialogs, Logs, Backup.

Where the canvas and Umbra disagree, Umbra wins: the Mac app never offers
a setting Umbra doesn't have.

## Testing

- **Never a public swarm or a real tracker.** Development builds start
  the helper with `UMBRA_LOOPBACK_ONLY=true` and their own data folder,
  against Umbra's made-up swarm (`just demo` in the umbra repo).
- The app's logic (API code, live feed, helper supervision) lives in a
  Swift package with tests of its own; some start a real helper in a
  temporary folder.
- Engine, VPN and API behaviour are tested in Umbra, not here.
- Visual checks at 1x, dark and light, against the canvas.
- Checks run on Dan's Mac until M5 (the homelab's runners are Linux).

## Risks

- **A fast-changing list** in SwiftUI: measured first in M1 at 100
  torrents, with AppKit's table as the fallback.
- **Sleep and wake:** the tunnel goes stale while the Mac sleeps. The
  kill switch should hold everything until it's back; M3 proves it.
- **macOS folder permissions:** the helper writes to the download folder.
  M0 checks that macOS asks once, in the app's name, and remembers.
- **Signing and notarizing an app with a helper inside** has its own
  rules; M5 is where that's learned, on a private build first.
- **Two things to release:** a Mac app version is tied to one Umbra
  version. A change that needs both is made in Umbra first.
