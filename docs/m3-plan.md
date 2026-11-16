# M3 · Mac integration

Drafted 2026-11-13. **Approved by Dan 2026-11-13**, with all four
recommendations under "Decisions" taken.

**Size: medium.** Six pieces. Five are ordinary Mac work with Apple's own
frameworks and no change to Umbra. One is delicate: what happens when the
Mac sleeps and wakes with a VPN up, because the app must be able to show
that nothing went out on the Mac's own connection in between.

**Done when:** the menu bar board of the canvas (board 8) works, torrent
files and magnet links open in Umbra from Finder and the browser, and a
sleep and wake cycle never sends anything outside the VPN.

## What gets built

- **Opening things in Umbra.** Double-clicking a `.torrent` file, clicking
  a magnet link in a browser, or dragging either onto the window or the
  Dock icon opens the Add sheet M1 built. Settings gets a General page
  with "Make Umbra the default for torrent files and magnet links".
- **The menu bar item** (board 8): the state at a glance (speeds, VPN,
  how many are active), Pause All, Resume All, Slow Mode, Open Umbra,
  Quit. Closing the window leaves torrents running here, as decided;
  Quit stops them.
- **Notifications from macOS:** a torrent finished, a torrent has a
  problem, the VPN went down or came back. Each kind can be turned off
  on the General page. Clicking one shows that torrent.
- **Keep the Mac awake** while something is downloading (a General page
  switch, on by default; never while only seeding, and never on battery
  unless asked).
- **Sleep and wake.** When the Mac wakes, the VPN tunnel is stale. Umbra's
  kill switch already holds torrents until the tunnel is back; this step
  proves it on the Mac, and makes the pill and banners say what is
  happening instead of looking stuck.
- **Launch at login** (a General page switch, off by default).

## What M3 leaves for later

- **M4:** Move to…, per-torrent and per-category limits, Logs, backup and
  restore, "Web interface for other devices".
- **M5:** signing. Until the app is signed, macOS may ask again about
  being the default app after each new build; that is expected.

## Decisions (Dan, 2026-11-13: all as recommended)

1. **Finished-download notifications on by default**, problems and VPN
   changes too. *Recommended.* (The alternative is everything off until
   chosen.)
2. **Keep awake only while downloading, not while seeding.** *Recommended:*
   seeding all night with the lid open would otherwise never let the Mac
   sleep.
3. **The menu bar item is always shown while Umbra runs.** *Recommended;*
   it is the only sign torrents are running once the window is closed.
   (The alternative is a switch to hide it.)
4. **A magnet link from the browser opens the Add sheet, never adds
   silently.** *Recommended,* as a web page could otherwise start a
   download without being asked.

## Steps

Each ends with `just lint` and `just test` passing and pictures Fable
checks, then a commit, as before.

### 0 · Check the canvas (Fable)
Board 8 against what Umbra has; correct it if it offers anything Umbra
doesn't.

### 1 · Opening files and links, drag and drop, the General page (Sonnet)

### 2 · The menu bar item and window closing (Sonnet)
Runs beside step 1.

### 3 · Notifications and keep awake (Sonnet)

### 4 · Sleep and wake (Opus)
First a reading of what Umbra does when its tunnel goes stale, with a
test in Umbra if one is missing. Then the Mac side: notice sleep and
wake, ask Umbra for the VPN's state at once, and show it. Any change
needed in Umbra is made there first, under its rules.

### 5 · Launch at login (Sonnet)
Small; may be folded into step 3.

Steps 0 to 5 built 2026-11-14 (step 5 went into step 3). Step 4 found no
way for traffic to leave the VPN across a sleep, but Umbra could say
"connected" for up to three minutes after a long sleep with a dead
tunnel; that is fixed in Umbra (a handshake must be recent by the
calendar too), and the app says "Checking VPN…" from sleep until Umbra's
fresh answer.

**Checkpoint (Dan):** open a torrent file and a magnet link from outside
the app; close the window and use the menu bar item; let a download
finish and see the notification; then, in the Release app with the VPN
up, close the lid for a minute, open it, and watch the pill and the
address peers see.

## Risks

- **Sleep and wake can't be fully tested by a machine.** Tests can fake
  a stale tunnel; only a real lid close on a real VPN shows the real
  thing, and that is Dan's to do.
- **Default-app handling is fiddly before signing** (see above).
- **Notifications need macOS's permission**, asked once; if refused, the
  General page says so and points to System Settings.
