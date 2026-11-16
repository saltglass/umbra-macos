# M1 · The main window

Drafted 2026-11-12; **done 2026-11-13** (both checkpoints passed by Dan;
the list was built on AppKit's table after the step 1 measurement).
**Size: large.** It is the whole everyday interface:
the list, the sidebar, the inspector's four tabs, adding and removing,
every menu and shortcut, and the VPN's states, each in dark and light.
None of it is hard on its own; there is a lot of it, and all of it is
looked at.

**Done when:** against Umbra's made-up swarm (`just demo`), Dan can do
everything he does on the web page's main screen, from boards 1 to 7 of
the canvas, and it stays smooth with 100 torrents changing at once.

**Not "day to day" yet.** Real use needs a VPN, and the VPN is set up in
Settings, which is M2. Until then the app only ever runs in development
mode, on 127.0.0.1. PLAN.md's wording for M1 changes to say so.

## What gets built

From the canvas, board by board, tied to Umbra's API:

- **Sidebar:** All, Downloading, Seeding, Paused, Queued, Errors;
  Categories; Tags; **Trackers** (on the web page, missing from the
  canvas: added); each with a live count. Free disk space at the foot.
- **The list:** Name, Size, Progress, Status, Down, Up, ETA, Ratio,
  Added to start with; the web page's other columns from the header's
  right-click menu. Sorting, resizing, reordering, many selected at
  once, search. Which columns, their widths and the sort are remembered
  on this Mac.
- **Toolbar:** add, pause, resume, remove, slow mode, the inspector
  switch, search, and the **VPN pill** with the address peers see.
- **Status bar:** free space, whether peers can connect in, DHT, total
  speeds.
- **Inspector** (right-hand side): General, Trackers (add, edit, remove,
  ask again), Peers, Files (a folder tree with tick boxes and
  priorities).
- **Add sheet:** a `.torrent` file, a magnet link or a web address;
  category, tags, start paused, choosing files. A magnet's files fill in
  when they arrive. A torrent already in the list offers to add its
  trackers to the one that's there.
- **Remove alert**, the **right-click menu**, the **Torrent menu** and
  the keyboard shortcuts drawn on the canvas.
- **Banners and states:** VPN connecting, down, and held; disk nearly
  full; the engine in trouble; "Reconnecting…" and "Saving…" from M0,
  now in the designed window. Wording and what each offers come from the
  web page's banners.
- **Empty states**, plain-English errors on a torrent, dark and light.

## What M1 leaves for later

- Settings, speed limit numbers, creating a category (M2). M1 assigns
  categories that exist and turns slow mode on and off.
- Opening files from Finder, drag and drop, notifications, the menu bar
  item (M3). Show in Finder is in M1: the inspector needs it.
- Move Data To…, per-torrent limits, Create torrent, Logs (M4). Their
  menu items appear when they work, not before.

## Where the canvas gives way

- **"Download pieces in order"** (Add sheet) comes out: Umbra doesn't do
  it yet.
- **"Local peer discovery"** (inspector) comes out: Umbra doesn't have
  it.
- **"Reconnect"** on the VPN-down banner becomes what Umbra offers
  ("Check again"); Umbra reconnects by itself.

## Decisions (Dan, 2026-11-12)

1. **As native as possible.** macOS draws everything: the window,
   sidebar, toolbar, controls, selection and accent colour are the
   system's (so the person's own accent colour applies), with SF
   Symbols for icons. Status colours are the system's green, orange and
   red. No colours of Umbra's own. The canvas is followed for layout,
   wording and what goes where, not for its colours.
2. **Remove deletes, it doesn't Trash.** Umbra deletes files itself, and
   knowing which files are a torrent's is engine logic that mustn't be
   copied into Swift. The alert says "Also delete the downloaded files
   (size)". A real Trash would be an addition to Umbra, later.
3. **The list's settings live on this Mac**, not in Umbra's shared
   preferences, so the Mac app and the web page don't rearrange each
   other's columns.
4. **Built for 100 torrents**, not thousands.

## Steps

Each step ends with `just lint` and `just test` passing, and pictures of
the result that Fable checks against the canvas before the next begins.

### 1 · Groundwork (Opus)
- **Pictures without a screen.** A development command that draws any
  view with fixed sample data to an image file, at 1x, dark and light.
  This is how every later step is checked, since Claude can't see the
  screen.
- **A stress feed:** 100 made-up torrents changing every second, with
  no Umbra involved (Dan, 2026-11-12: 100 is the size to build for;
  it is also Umbra's own memory budget).
- **Plain types for the views** in front of the generated API code: a
  torrent as the list shows it; sizes and speeds counted in 1024s, ETA,
  dates, and the plain-English status of each torrent, all matching
  Umbra's web page (`web/src/lib/format.ts`, `torrents.ts`, with their
  test cases carried over).
- **An actions layer:** every change goes through one place that calls
  Umbra and turns a refusal into a readable message.
- **Two helpers at once:** tests give their helper a free peer port, so
  `just test` works while the app is open (left over from M0).
- **The measurement:** the SwiftUI table with the stress feed. If
  scrolling, selecting and sorting stay smooth, it stays. If not, the
  list becomes an AppKit table now, before anything is built on it.

### 2 · The window and the list (Sonnet; Opus if the list goes AppKit)
Sidebar with filters and counts, toolbar, the list with its columns,
sorting, selection and search, status bar, empty states.

**Checkpoint 1 (Dan):** look at it on `just demo`. The layout and
colours are settled here, before the rest is built on them.

### 3 · The inspector (Sonnet)
The four tabs, including tracker editing, the file tree with priorities,
and Show in Finder.

### 4 · Actions (Sonnet)
The right-click menu, the Torrent menu, shortcuts, the Remove alert,
slow mode, categories and tags from the menu, copy magnet link and info
hash, export `.torrent`.

### 5 · Adding (Opus)
The Add sheet for all three kinds, the magnet that fills in while the
sheet is open, duplicates, refusals in plain English.

### 6 · The VPN and the banners (Sonnet)
The pill's states, the banners, and M0's "Reconnecting…", "Saving…" and
failure views redrawn for the real window. The made-up states are
checked from pictures; the real ones against a helper.

**Checkpoint 2 (Dan):** use it on `just demo` as you would the web page:
add, pause, remove, choose files, edit a tracker. Then the stress feed
at 100.

## Order and cost

Step 1 first, alone. Steps 3 to 6 each depend on step 2's window, and
touch different files, so 3 and 4 run side by side, then 5 and 6.
Each subagent gets a brief of its own with the files, the board, the
API calls and the tests, and is told not to read the plans.

## Risks

- **The list with 100 rows all changing:** unlikely to be a problem at
  this size; settled in step 1 all the same, with AppKit as the way out.
- **Pictures aren't the screen.** Drawn images miss live things (hover,
  focus, scrolling, window resizing). The two checkpoints are where Dan
  catches what pictures can't.
- **The canvas is a web drawing of a Mac app.** Where a system control
  doesn't quite match it, the system control wins; step 2's checkpoint
  is where that's judged.
