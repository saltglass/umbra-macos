# M4 · The rest of parity

Drafted 2026-11-14. **Approved by Dan 2026-11-14, without the web
interface:** "Umbra in docker is for that." The app never listens on the
network. **Checkpoint passed 2026-11-15** (Dan: "everything works").

**Size: medium.** Five pieces. Four are ordinary screens tied to things
Umbra already does and tests (limits, moving, creating, logs). One needs
care and a small change inside Umbra: backup and restore (Umbra refuses
the app's own launch identity today).

**Done when:** nothing on the web page is missing from the Mac app, apart
from the three things PLAN.md leaves out on purpose (saving files to your
computer, Appearance, and sign-in settings).

## What gets built

- **Move Data To…** in the torrent menu: choose a folder, Umbra moves the
  files, the list shows "Moving" as it already can.
- **Limits.** A torrent's own download and upload limits and seeding
  goals (menu → "Limits…", and in the inspector). A category's own
  limits and goals in its sheet on Settings → Downloads.
- **Create Torrent…** (File menu): choose a file or folder on this Mac,
  trackers, private or not, piece size left to Umbra; see the result and
  start seeding it or save the `.torrent` file.
- **Logs window** (Window → Logs): Umbra's live log with a level filter,
  search, and "Save Logs…".
- **Backup and restore** (Settings → General): "Save a Backup…" writes
  Umbra's backup file where you choose. "Restore from Backup…" replaces
  this Mac's Umbra settings and torrent list with a backup's, after a
  plain warning, and restarts the helper.

## Changes needed in Umbra

- **Backup for the app itself.** Downloading a backup answers 403
  `account_needed` to the launch identity. The app's own helper should be
  allowed to make one. Restore: Umbra's API has no restore call today
  (the web page restores at first-run setup), so the plan starts by
  reading how restore works and choosing the smallest safe way for the
  app to do it. This is auth code, so Opus, with tests.

## Decisions (Dan, 2026-11-14)

1. **No web interface for other devices.** Umbra in Docker is for that.
2. **Restore asks twice:** once to choose the file, once in an alert that
   says the current torrent list and settings are replaced.
3. **Create Torrent only offers files on this Mac**, through the normal
   file chooser.

## Steps

Each ends with `just lint` and `just test` passing and pictures Fable
checks, then a commit.

### 0 · The canvas (Fable)
The canvas has no boards for the Logs window or the Create sheet. None
are drawn: each builder's brief carries the layout and wording, following
the sheets and windows already built.

### 1 · Move, and a torrent's and a category's limits (Sonnet)

### 2 · Create Torrent (Sonnet)
Runs beside step 1.

### 3 · Logs window (Sonnet)

### 4 · Backup and restore (Opus, starting in Umbra)

**Checkpoint (Dan):** on `just demo`: move a torrent, set limits, make a
torrent from a folder, watch the logs, save a backup and restore it.

## Risks

- **Restore replaces data.** It keeps a copy of the current data folder
  beside it before replacing anything, and says where.
