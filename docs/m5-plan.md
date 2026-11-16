# M5 · Release

Drafted 2026-11-14, approved by Dan the same day as a public, signed
release. **Changed by Dan 2026-11-15: no Apple Developer account for
now.** "I'm likely to be the only person who ever uses it. If that
changes, I'll pony up the $99." So 0.1.1 is a private release: unsigned
by Apple, kept on Forgejo. See "The release without Apple" below; the
signed and public parts of this plan stay written down for the day that
changes.

**Size: medium on the recommended route, small on the private one.** The
app itself barely changes: an icon, an About window, a version number, a
README. The cost is in Apple's signing and notarization, which nothing in
this project has done before, which is strict about an app with a helper
program inside it, and which can only be tried once a paid Apple Developer
account exists.

**Done when:** a copy downloaded in a browser opens on a Mac that has
never seen Umbra, with no warning to get round.

## Where things stand

- This Mac has no signing certificate and there is no Apple Developer
  account. Today's builds are signed "ad hoc": fine on the Mac that built
  them, blocked by macOS on any other Mac until the person goes to System
  Settings → Privacy & Security → "Open Anyway".
- Because an ad hoc signature changes with every build, macOS may ask
  again about folder access, the default app for torrents and opening at
  login after each new build. A real certificate ends that.
- The app is built against a commit on Umbra's `next` branch that is only
  on Forgejo. A public Mac app must be built from a public Umbra: the GPL
  requires that anyone who gets the app can get the exact source of
  everything inside it.
- There is no Mac among the homelab's runners. Checks run on Dan's Mac by
  hand.

## What gets built

- **The app icon:** Umbra's shield-and-eclipse mark in its violet and
  cyan, in the shape macOS gives app icons, in every size macOS wants.
  The "Umbra Dev" build gets the same icon with a visible "DEV" band so
  the two are never confused in the Dock.
- **About Umbra** (the standard menu item): the app's version, the
  version of Umbra inside it, the licence (GPL-3.0), where the source is,
  and the licences of what the app carries (the torrent engine,
  WireGuard, Apple's API libraries).
- **Version numbers.** The app gets its own, starting at 0.1.1, in one
  place (`Config/Version.xcconfig`), with a `CHANGELOG.md` like Umbra's.
- **`just dist`:** one command that makes the Release build, signs it,
  and produces `Umbra-<version>.dmg` (a disk image with the app and a
  shortcut to Applications) and its checksum. Made with macOS's own
  tools; no new dependency.
- **The README:** what it is, what it needs (Apple silicon, macOS 26),
  how to install, where the data lives, how to remove it, how it differs
  from Umbra in Docker, and how to build it from source.
- **On the signed route:** a Developer ID signature on the app and the
  helper, Apple's stricter "hardened" mode, notarization (Apple scans the
  disk image and returns a stamp that is attached to it), and a check
  that macOS accepts the result as a downloaded file.
- **On the public route:** the repo on GitHub beside Umbra
  (`saltglass/umbra-macos`), checks on GitHub's Mac runners on every
  push, and a release page with the disk image.

## Decisions (Dan, 2026-11-14)

1. **Public, signed and notarized.** Dan pays for the Apple Developer
   account ($99 a year). (The alternatives were private and unsigned, or
   public and unsigned.)
2. **Umbra 0.4.0 is released first**, after its M8 and M10 checks on a
   real server, and the Mac app is built from that tag.
3. **The first version is 0.1.1**, counted separately from Umbra's;
   About shows both.
4. **The icon is Umbra's mark as it is**, violet and cyan on a dark
   tile. Dan sees pictures before it goes in.
5. **Checks on every push: Fable's choice.** GitHub's Mac runners (free
   for a public repo) run lint, the tests and a build, if they have a
   new enough Xcode; otherwise a hook on this Mac before every push.
   Releases are always built and signed on Dan's Mac, so the signing
   certificate never leaves it.
6. **Umbra's secret key stays in the data folder** for this release, as
   in Docker; not the Keychain.

## What only Dan can do (route A)

- Enrol in the Apple Developer Program with his Apple ID (Apple can take
  a day or two to confirm an individual).
- Sign in to that account in Xcode once, so the Developer ID certificate
  is made in this Mac's Keychain.
- Make an app-specific password for notarization. It is stored in the
  Keychain by Apple's own tool, never in the repo or a file.

## Steps

Each ends with `just lint` and `just test` passing, and a commit. Steps
1 to 3 are the same on every route and can start as soon as the plan is
approved.

### 1 · The icon and About (Sonnet) — built 2026-11-14
The icon files generated from `umbra-icon.svg` by a script, so it can be
remade; pictures at 1x for Dan. The About window and the licences list.

### 2 · Versions and the disk image (Sonnet) — built 2026-11-14
`VERSION`, `CHANGELOG.md`, `just dist` making an ad hoc signed disk
image, hardened mode switched on and the whole app checked under it
(helper start, file choosers, notifications, open at login) on the
development build.

### 3 · The README (Sonnet) — built 2026-11-14

**Where it stands (2026-11-14):** `just dist` makes
`build/dist/Umbra-0.1.1.dmg`, signed ad hoc, with the icon, About and the
licences inside. The version is in `Config/Version.xcconfig` (not a
`VERSION` file: Xcode reads it directly). Hardened mode is on for the
development build too, which opens, starts its helper and quits cleanly
under it. Dan looked at the icon 2026-11-15: "The icon is fine, keep
it." Steps 4 and 5 wait on the Apple Developer
account, the M4 checkpoint and Umbra 0.4.0.

## The release without Apple (Dan, 2026-11-15)

**Size: small.** Nothing new to learn: the disk image already builds.

- **Private.** The repo stays on Forgejo; nothing goes to GitHub, and
  Umbra 0.4.0 is not needed first. `UMBRA_VERSION` names the exact
  Umbra commit built in (453d079 on `next`).
- **Unsigned by Apple** ("ad hoc"). On the Mac that built it the app
  opens normally. Any other Mac blocks it once, until "Open Anyway" in
  System Settings → Privacy & Security. The README says so.
- **macOS may ask its questions again after each new version** (folder
  access, default app, open at login): an ad hoc signature is different
  for every build. Accepted for now.
- **Checks:** a hook on this Mac runs the style check and the tests
  before every push (`.githooks/pre-push`).
- **About** has "Umbra on GitHub" (the server's public source) instead
  of "Source Code", since the Mac app's own source is private.
- **Releasing a version:** set it in `Config/Version.xcconfig`, give it
  a dated section in `CHANGELOG.md`, run `just dist`, install from the
  disk image, then tag (`v0.1.1`) and push.

**Checkpoint (Dan):** quit the Release app he has been running; open
`build/dist/Umbra-0.1.1.dmg`; drag Umbra to Applications; open it from
there. It shows the icon and, in About, version 0.1.1; his torrents and
VPN are as he left them. Then 0.1.1 is tagged.

**Passed 2026-11-15** (Dan: "Looks good"), running from Applications in
hardened mode. Tagged `v0.1.1`. M5 is done.

## The source on GitHub (Dan, 2026-11-15, after the release)

Dan asked for the repo on GitHub, public, with a clean history: one
"Umbra for macOS 0.1.1" commit, as Umbra's own public history began,
because the working history names the home server's address. No disk
image is published there (it would be unsigned). `scripts/common.sh`
now fetches Umbra from GitHub (`UMBRA_REPO` overrides it). Later the same day Dan
asked for Umbra's `next` on GitHub and for the disk image as a download:
a fresh clone of the public repo builds, and release v0.1.1 on GitHub
carries the unsigned disk image and its checksum.

## If it is signed later (not being done now)

### 4 · Signing and notarization (Opus; route A, once the account exists)
`just dist` signs the helper, then the app, with the Developer ID;
sends the disk image to Apple; attaches the stamp; then asks macOS
itself whether it would let a downloaded copy open. Fails loudly at
whichever stage refuses. Nothing secret in the repo.

### 5 · Going public (Fable; routes A and C)
Umbra 0.4.0 released and `UMBRA_VERSION` pointed at it; a read through
the repo's history for anything private; `scripts/common.sh` fetching
Umbra from GitHub instead of the home server's address (it can't until
0.4.0 is there); screenshots for the README; the GitHub repo; the checks
workflow; tag `v0.1.1`; the release page with the disk image and its
checksum.

**Checkpoint (Dan):** quit the Release app; download the disk image in
Safari; drag Umbra to Applications; open it. It opens with only macOS's
normal "downloaded from the internet" question, shows the right icon and
version, and his torrents and VPN are as he left them. If the family Mac
mini is handy, open it there once and quit, as the "never seen Umbra"
test.

## Risks

- **Notarization refuses the helper.** The Go program must be signed
  with the same identity, in hardened mode, before the app around it.
  Step 2 turns hardened mode on early so anything it breaks shows up
  before Apple is involved.
- **macOS asks its questions once more.** The first signed build is a
  new identity to macOS: folder access, default app and open at login
  are asked or set again, once. Data is untouched (same name, same data
  folder).
- **GitHub's Mac runners may lag** behind the Xcode this needs (Swift
  6.2, macOS 26). Checked in step 5; the fallback is the push hook.
- **Something private in the history.** `CLAUDE.local.md` has always
  been ignored, but step 5 reads the whole history before anything is
  pushed to GitHub.
