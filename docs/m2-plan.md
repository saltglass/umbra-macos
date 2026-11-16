# M2 · Settings

Drafted 2026-11-13. **Approved by Dan 2026-11-13**, with all four
recommendations under "Decisions" taken.

**Size: medium.** Seven pages of ordinary controls, each tied to one
group of Umbra's settings that already exists and is already tested in
Umbra. The window, the list, the actions layer and the picture tool are
all there from M1. One page is delicate: the VPN page handles VPN
configurations (which contain private keys) and decides whether torrents
may run without a VPN.

**Done when:** every setting on the web page's Settings can be changed
from the Mac app's Settings window (⌘,), apart from the three things
PLAN.md leaves out on purpose (Appearance, sign-in and security, which
only matter with "Web interface for other devices" in M4).

**What M2 unlocks.** With a VPN set up, the app can be used for real for
the first time. That first real run is the last checkpoint, and Dan does
it himself with his own VPN configuration; Claude never sees or tests a
real provider.

## What gets built

The Settings window, with a toolbar of pages as Mac apps have:

- **Downloads:** the download folder, the folder for unfinished
  downloads, the watch folder, the free-space warning, and
  **categories** (add, rename, remove, each with its own folder). This
  also finishes what M1 left: a category can be created.
- **Speed:** download and upload limits, slow mode's limits, and slow
  mode on a schedule.
- **Queue and seeding:** how many run at once; the seeding goals (ratio,
  time seeding, time with no one downloading).
- **Connection:** the peer port and the ways of finding peers that Umbra
  has.
- **VPN:** saved VPNs (add from a WireGuard file or pasted text, rename,
  remove, choose which to use, order them), switching to the next one
  when the current one has been down for a while, and what happens with
  no VPN ("Don't start torrents", or start without one, which says
  plainly that peers will see the real address).
- **Notifications:** email alerts (server, sender, recipient, which
  events), with "Send a test".
- Small things M1 pointed at Settings: the VPN popover and the
  held-VPN banner get their buttons ("Open VPN Settings…", "Start
  Without VPN…" behind a confirmation).

## What M2 leaves for later

- **M3:** anything about the Mac itself: default app for torrents and
  magnet links, the menu bar item, notifications from macOS, keeping the
  Mac awake. No "General" page until they exist.
- **M4:** per-torrent and per-category speed limits, Logs, backup and
  restore, "Web interface for other devices" (with sign-in and security).

## The canvas is corrected first

As decided on 2026-11-12. The Settings board was drawn before the plan
and offers things Umbra doesn't have.

- **Comes out:** "Map port with UPnP", Encryption, Disk cache, Local
  peer discovery, "Send torrent traffic through wg0", "Check for IP
  leaks", "Reset All Settings…".
- **Goes in:** saved VPNs and switching when one is down, the seeding
  goals beyond ratio, the watch and unfinished folders, categories,
  email notifications.
- **Moves to later boards:** the General page's Mac items (M3), "Web
  interface for other devices" and "Show Logs…" (M4).

## Decisions (Dan, 2026-11-13: all as recommended)

1. **Changes apply as they're made, with no Save button**, as in macOS's
   own Settings. A number or a folder is sent when the field is left or
   Return is pressed. If Umbra refuses a value, the field goes back to
   what it was and says why. *Recommended.* (The alternative is a Save
   button per page, like the web page.)
2. **A VPN configuration is handed straight to Umbra and never kept by
   the Mac app:** not in its own settings, not in logs, not in pictures.
   It lives in Umbra's data folder, protected as in the Docker version.
   *Recommended; the Keychain is reconsidered at M5 as already planned.*
3. **"Start without VPN" always asks first**, in an alert that says peers
   will see this Mac's real address. *Recommended.*
4. **The first real run uses the real data folder** (`~/Library/
   Application Support/Umbra`), separate from development's. It needs a
   Release build, which M0 never ran, so M2 includes running one.
   *Recommended.*

## Steps

Each step ends with `just lint` and `just test` passing and pictures
that Fable checks, then a commit, as in M1.

### 0 · Correct the canvas (Fable)
The Settings board redrawn to match the list above.

### 1 · Groundwork (Opus)
A settings layer in UmbraKit: read and change each group through one
place, keep the window in step when settings change elsewhere (the web
page, a schedule), turn refusals into readable messages, and never let a
half-typed value be sent. The Settings window's frame and page switcher.
A Release build run once against a throwaway data folder.

### 2 · Downloads, Speed, Queue and seeding (Sonnet)
Including categories and the folder pickers.

### 3 · Connection and Notifications (Sonnet)
Runs beside step 2.

### 3½ · Hold until a VPN is chosen (Opus, in Umbra)
Found in step 1: a fresh Umbra with no VPN runs on the Mac's own network
at once (peer port open, DHT joined). Dan chose (2026-11-13) that the Mac
app holds everything until a VPN is set up or "Start without VPN" is
chosen. An opt-in Umbra setting, off for Docker, which the app turns on.

### 4 · VPN (Opus)
The saved VPNs, importing, ordering, switching when down, and running
without a VPN. Tested against Umbra's made-up VPN endpoint only.

Steps 0 to 4 built 2026-11-13. After step 4: the held-VPN banner crashed
the main window (fixed, 3d72c75), and the forwarded port got a box on the
VPN page itself (ecb46b7). Dan passed the first half of the checkpoint
below on 2026-11-13, and the same day ran the Release app with his own
VPN and downloaded a Fedora release through it. **M2 is done.**

**Checkpoint (Dan):** change settings on `just demo` and see them on the
web page too. Then the first real run: a Release build, his own VPN
file, one real torrent of his choosing, watching the pill and the
address peers see.

## Risks

- **The VPN page is where a mistake matters.** A wrong default could
  start torrents with no VPN. Umbra enforces the kill switch itself; the
  page only asks, and "start without" is never a default or a single
  click.
- **Settings changed in two places at once** (Mac and web page): the
  last change wins, as on the web page, and the window shows what Umbra
  now has.
- **The first Release build** may show problems development builds hide
  (the helper's place in the app, macOS asking for folder access).
  Finding them is the point of running it here and not at M5.
