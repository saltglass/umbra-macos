# Umbra for macOS

A native Mac app for [Umbra](https://github.com/saltglass/umbra), the
BitTorrent client. The Umbra engine runs inside the app, so you get the
same engine and the same VPN protection, in a normal Mac window with a
menu bar item, notifications and the usual Mac menus.

<!-- screenshot: docs/screenshots/main-light.png / main-dark.png, added at release -->

- **A VPN with a kill switch, built in.** Add your provider's
  WireGuard file and every torrent connection goes through the tunnel.
  If the tunnel drops, every torrent stops. Nothing falls back to your
  normal connection.
- **Only torrents use the VPN.** The rest of your Mac's traffic is left
  alone. There is nothing extra to install: no system extension, and no
  administrator password.
- **Nothing goes out before you choose.** On first launch every torrent
  is held until you add a VPN (or decide to go without one).
- **Private to your Mac.** The engine inside answers only on this Mac,
  and only to the app that started it. Nothing listens on your network.
- **A Mac app, not a web page in a window.** It uses the system's
  controls and menus, follows light and dark mode, and uses your accent
  colour.

## What it needs

- A Mac with Apple silicon (M1 or newer).
- macOS 26 or newer.

There is no build for Intel Macs.

## Install

1. Download `Umbra-0.1.2.dmg` from the
   [releases page](https://github.com/saltglass/umbra-macos/releases).
2. Open it and drag Umbra to the Applications folder.
3. Open Umbra from Applications.

**The app is not signed with an Apple developer certificate.** macOS
blocks a downloaded copy the first time and says it can't check the
app. To allow it: open
System Settings → Privacy & Security, scroll down to the message about
Umbra, and choose "Open Anyway". macOS asks once and then remembers.

For the same reason, macOS may ask again about folder access, being the
default app for torrents and opening at login after you install a new
version.

To check that your download is the one that was published, download the
`Umbra-0.1.2.dmg.sha256` file into the same folder and run this in
Terminal:

```sh
shasum -a 256 -c Umbra-0.1.2.dmg.sha256
```

It should print `Umbra-0.1.2.dmg: OK`.

Umbra does not update itself. A new version is installed the same way,
replacing the old app. Your settings and torrents stay
where they are.

## First launch and the VPN

The first time you open Umbra, every torrent is held. Held means
stopped, with nothing touching the network: no trackers, no peers. A
banner above the list says so. You have two choices.

**Add a VPN.** Open Settings → VPN and choose "Add from File…" (or drop
the file on the page, or use "Paste Configuration…"). You need a
WireGuard configuration file from your VPN provider. Once a VPN is added,
torrents start, and only through it. A small VPN indicator in the window
shows whether the VPN is up and the address peers see. You can save more
than one VPN and pick which one is in use. Umbra can also move to the
next saved VPN if the one in use stays down for a few minutes you
choose; it never moves to your normal connection.

**Start without a VPN.** Choose "Start Without VPN…" on the same page.
Umbra asks first, and tells you that torrents will then run on this
Mac's own connection and every peer will see its real IP address. It
remembers your choice, so it does not hold torrents again at the next
launch. Adding a VPN later puts torrents behind it.

If you add a VPN whose provider forwards a port to you, enter it under
"Forwarded port" in Settings → VPN so peers can connect in.

## What it does

- **The torrent list.** A sidebar filters by status, category, tag and
  tracker. Select a torrent to see its details in the inspector, with
  tabs for General, Trackers, Peers and Files.
- **Adding torrents.** Add a `.torrent` file, a magnet link or a web
  address, or drag and drop one onto the window. `.torrent` files and
  magnet links you open from Finder or your browser open Umbra's Add
  sheet. Nothing is added until you press Add. (Settings → General has a
  button to make Umbra the app for them.)
- **Categories and tags.** Each category can have its own folder, speed
  limits and seeding goals.
- **Speed limits.** One pair for everything, a lower pair for slow mode,
  and a schedule that turns slow mode on and off by day and hour. You
  can also set limits on a single torrent ("Limits…" in its menu).
- **Queue.** Choose how many torrents download and seed at once, and
  reorder the queue.
- **Seeding goals.** Stop seeding at a ratio, after a seeding time, or
  after a time with nothing uploaded.
- **Move Data To…** moves a torrent's files to another folder.
- **Create Torrent…** (File menu) makes a `.torrent` file from a file or
  folder on your Mac.
- **A watch folder** (Settings → Downloads): `.torrent` files put there
  are added for you.
- **Logs.** Window → Logs shows what Umbra has been doing, in plain
  words, which helps when you report a problem.
- **The menu bar item.** Shows the state of your downloads and the VPN,
  with slow mode, Pause All, Resume All and Quit.
- **Notifications.** Optional alerts when a download finishes, when a
  torrent has a problem, and when the VPN goes down or comes back. Each
  has its own switch in Settings → General. (Settings → Notifications is
  separate: it sets up emails through a mail service you already have.)
- **Keep the Mac awake while downloading.** Optional, in Settings →
  General. The screen can still sleep, and seeding alone never keeps the
  Mac awake.
- **Open at login.** Optional, in Settings → General.

Closing the window does not stop anything. Torrents keep running and the
menu bar item stays. Choose Umbra → Quit Umbra (or Quit in the menu bar
panel) to stop them.

After the Mac wakes from sleep, Umbra checks the VPN again.

## How it differs from Umbra in Docker

The Mac app has the same engine, but it is built for one person on one
Mac. A few things are left out on purpose:

- **No web interface.** You cannot open it from your phone or another
  computer.
- **No sign-in settings.** There is nothing to sign in to. Only the app
  can talk to the engine.
- **No qBittorrent-compatible API.** Apps such as Radarr and Sonarr
  cannot use it as a download client.
- **No "save to your computer".** The files are already on your Mac.
  Use "Show in Finder" on a torrent.
- **No Appearance settings.** It follows your Mac's light or dark mode
  and accent colour.

If you need any of these, for example a web page you can open from
your phone, or an app such as Radarr that sends it downloads, run
[Umbra in Docker](https://github.com/saltglass/umbra) instead.

## Where your data lives

Umbra keeps its settings, its torrent list and your saved VPNs in:

```
~/Library/Application Support/Umbra
```

The saved VPNs are locked with a key kept in that same folder. Your
downloaded files are not in there. They are in the folder you chose in
Settings → Downloads.

### Backing up and restoring

Settings → General has a Backup section.

- **Save a Backup…** writes one file (a `.tar.gz`) with your settings,
  the torrent list and your saved VPNs. It does not hold the downloaded
  files. Keep it private, because it holds your VPNs.
- **Restore from Backup…** replaces Umbra's settings, torrent list and
  saved VPNs with the ones in a backup file. It asks you to confirm
  first. Umbra keeps the old data in a folder named
  `before-restore-` and the date, inside its data folder, and downloaded
  files are not touched. Umbra stops while it restores, then starts
  again.

Only Umbra on the same Mac can restore a backup, because the VPNs in it
are locked with that Mac's key.

### Removing Umbra

1. If "Open Umbra at login" is on, turn it off first (Settings →
   General).
2. Quit Umbra.
3. Delete Umbra from the Applications folder.
4. To remove its settings and torrent list as well, delete the
   `~/Library/Application Support/Umbra` folder.

Deleting the app never deletes your downloaded files, and neither does
deleting the data folder.

## Building from source

You need Xcode 26 or newer, plus [just](https://just.systems),
[XcodeGen](https://github.com/yonaskolb/XcodeGen) and Go, all
available from Homebrew. The Umbra engine is built from source too, so
you also need whatever Umbra's own build needs (see "Developing" in
[its README](https://github.com/saltglass/umbra)).

- `just build` builds the development app, named "Umbra Dev". It has its
  own data folder and its own app identity, and it never leaves this
  computer: it reaches nothing but the Mac's own loopback network.
- `just run` builds it and opens it.
- `just test` runs the tests. `just lint` checks the code style.
- `just dist` makes the disk image, `build/dist/Umbra-<version>.dmg`,
  with its checksum. It is signed "ad hoc" (no Apple certificate)
  unless you set `UMBRA_SIGN_IDENTITY` to a Developer ID.

The file `UMBRA_VERSION` names the exact version of Umbra that is built
in; the build fetches it from Umbra's public repository. Set `UMBRA_SRC` to the folder of your own copy of Umbra's source,
for example `UMBRA_SRC=~/code/umbra just build`. `just` lists every recipe, and the
`Justfile` has a comment on each.

## Licence

GPL-3.0. See [LICENSE](LICENSE). Umbra, which runs inside the app, is
GPL-3.0 too. In the app, Umbra → About Umbra → Licences… lists the
licence of everything else inside it.
