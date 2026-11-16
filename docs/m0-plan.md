# M0 · Foundation

Drafted 2026-11-12. **Size: medium.** Two small, careful changes inside
Umbra (one touches sign-in, so it gets full tests), then a new repo with
the unglamorous parts every later milestone stands on: building the
helper into the app, starting and stopping it, and the live feed.

**Done when:** the app opens and shows made-up torrents updating live,
quitting it stops the helper cleanly, and killing the app stops the
helper too.

Nothing here is the designed interface. M0's window is a plain list; the
canvas starts in M1.

## Part A: in Umbra (`~/Forgejo/umbra`, branch `next`)

All of it off unless asked for. With none of the new variables set, Umbra
behaves exactly as before; a test pins that.

### A1 · Listen on a chosen address (Opus)
- `UMBRA_LISTEN`, such as `127.0.0.1:0`. Unset: every interface on
  `UMBRA_PORT`, as today. Port 0 means "pick a free one".
- `UMBRA_ADDR_FILE`: when set, Umbra writes the address it ended up on to
  this file once it is listening (written whole, then renamed into
  place), so the app knows where to connect.
- `umbra healthcheck` follows the same setting.
- Why not a Unix socket, which would be more private still: Apple's
  networking can't speak HTTP over one without a large extra dependency.
  127.0.0.1 plus the token gives the same result: a web page in a
  browser on the Mac can't send the token's header to another origin,
  and another program can't guess it.

### A2 · The launch token (Opus)
- `UMBRA_LAUNCH_TOKEN`: a request carrying it in the
  `X-Umbra-Launch-Token` header is the owner, with no account and no
  sign-in screen.
- Refused unless **all** of these hold: `UMBRA_LISTEN` is a loopback
  address; the connection really comes from loopback (the socket's
  address, never a forwarded header); the token is at least 32
  characters. Umbra refuses to start with a token and a non-loopback
  listener.
- Compared in constant time; hidden from every log line
  (`internal/logs/redact.go`); never in an API answer.
- With a token set and no account yet, `/auth/state` tells the token's
  holder it is signed in, not "set up an account". Everyone else sees
  what they see today.
- Work out how an owner with no account fits `/me/preferences` (the
  bypass list has the same question; follow its answer).
- Tests, in the style of the existing auth tests: right token; wrong
  token; none; a token on a non-loopback listener; a spoofed
  `X-Forwarded-For`; the token never appears in the logs; the
  qBittorrent API (`/api/v2`) does **not** take it.

### A3 · Stop when the app is gone (Sonnet)
- `UMBRA_EXIT_WITH_PARENT=true`: when the helper's standard input
  closes (which happens when the app that started it dies), it shuts
  down as it does for a normal stop, saving the engine's records.
- Test: start it with a pipe, close the pipe, see a clean exit.

### A4 · A Mac build, and the paperwork (Sonnet)
- `just build-mac`: the binary for Apple silicon, the web page embedded
  as usual (M4's "Web interface for other devices" needs it).
- The release workflow attaches it to GitHub releases.
- `CLAUDE.md`: the "a desktop app" non-goal becomes a pointer to this
  project; the new variables join "Config". `README.md` and
  `CHANGELOG.md` say what they are for.

**Checkpoint A (Fable):** `just lint` and `just test` pass in Umbra; the
diff to `internal/auth` is read line by line; by hand, a helper started
with a token answers `curl` with it and refuses without. Committed to
`next` on Forgejo only when Dan says so. It reaches GitHub with Umbra's
next release.

## Part B: this repo

### B1 · The skeleton (Sonnet)
```
umbra-macos/
  UMBRA_VERSION          the Umbra commit or tag this app is built on
  project.yml            the Xcode project, as text (XcodeGen)
  Justfile
  App/                   the app target: views only
  UmbraKit/              Swift package: the logic, with its tests
    Sources/UmbraAPI/      openapi.yaml (a copy) and the generated code
    Sources/UmbraKit/      connection, helper supervision, live feed
    Tests/
  scripts/               building the helper, copying the API file
  docs/
```
- `git init`, `LICENSE` (GPL-3.0), `.gitignore` (build output, the
  `.xcodeproj`, `CLAUDE.local.md`), `.editorconfig`, a pre-commit hook
  that runs `just lint`.
- Commands, kept in step with CLAUDE.md:
  - `just helper`: build Umbra at `UMBRA_VERSION` into `build/`.
    `UMBRA_SRC=~/Forgejo/umbra` builds from that folder as it stands,
    for work that changes both.
  - `just gen`: copy `api/openapi.yaml` from the same Umbra and
    regenerate the Swift API code.
  - `just build`, `just run`, `just test`, `just lint`, `just fmt`.
- The app: macOS 26, Apple silicon, signed to run on this Mac only, not
  sandboxed. The helper is copied into the app at
  `Contents/Helpers/umbra`.
- A test fails if the copied `openapi.yaml` isn't the pinned version's.

### B2 · The connection and the API code (Sonnet)
- `Connection`: an address plus a credential (launch token or API key).
  One type for the bundled helper, a development server, and remote
  control later.
- The generated client from swift-openapi-generator, over URLSession,
  with the credential added to every request.
- Tests against a small fake server: the header is sent; Umbra's error
  answers become readable Swift errors.

### B3 · Looking after the helper (Opus)
- Start: make the token, choose the data folder, start
  `Contents/Helpers/umbra serve` with `UMBRA_LISTEN=127.0.0.1:0`,
  `UMBRA_ADDR_FILE`, `UMBRA_LAUNCH_TOKEN`, `UMBRA_EXIT_WITH_PARENT`,
  `UMBRA_DATA_DIR`. Wait for the address file, then for `/ping`.
- If it doesn't come up in 20 seconds: a plain message and the last
  lines of its log, never a blank window.
- If it dies while running: restart it, at most three times in five
  minutes, then stop and say so. The window shows "Reconnecting…"
  meanwhile.
- Quit: ask it to stop, wait up to 30 seconds while the engine saves
  (the window says "Saving…"), only then force it.
- One copy only: a second launch brings the first to the front.
- Data folders: `~/Library/Application Support/Umbra` for release
  builds; `Umbra-Dev` for development builds, which always set
  `UMBRA_LOOPBACK_ONLY=true`. A test pins that a development build can't
  be pointed at the real folder.
- The helper's output goes to a log file in the data folder (Umbra
  already hides secrets from it).
- Tests with a real helper in a temporary folder: comes up; the token
  works and a wrong one doesn't; clean stop; killed helper is
  restarted; killed app means the helper exits.

### B4 · The live feed (Opus)
- Read Umbra's stream (`GET /api/v1/events`): a snapshot of every
  torrent, then changes. Umbra's `web/src/hooks/feed.ts` and
  `feed.test.ts` are the reference; its test cases are carried over.
- A dropped stream reconnects and starts from a fresh snapshot.
- The result is one observable store the views read. Updates are
  applied in batches so a list of thousands doesn't redraw per event.
- Tests: the stream parser on awkward input (split lines, comments,
  reconnects); the store against the carried-over cases.

### B5 · A window that proves it (Sonnet)
- One plain window: a list with name, progress, status, down and up
  speed; a line of text for the VPN state; the "Reconnecting…" and
  "Saving…" states from B3.
- Development can attach to a running `just demo` in the umbra repo
  instead of starting a helper (its address and API key, in the
  scheme's settings), which gives about 30 torrents that really move.

**Checkpoint B (Fable):** `just lint` and `just test` pass. By hand:
the app opens onto `just demo`'s torrents and they move; started
normally, the helper comes up on its own; Quit leaves no `umbra`
process; `kill -9` on the app leaves none either; `kill -9` on the
helper shows "Reconnecting…" and recovers. Activity Monitor and
`lsof` confirm the helper listens on 127.0.0.1 only.

## Order

A1 and A2 first (B3 can't be finished without them), A3 and A4 beside
them. B1 and B2 can start at once, in parallel with Part A. B3 and B4
follow, then B5.

## Things M0 settles for later milestones

- Whether macOS asks for folder permission in the app's name when the
  helper writes to `~/Downloads`, and remembers the answer.
- How long the helper takes to start and stop with a few hundred
  torrents (decides whether launch needs a progress state).
- Whether the generated API code is pleasant enough to use directly in
  views, or needs a thin layer of plain Swift types in front of it.

## Not in M0

The designed interface, Settings, adding or removing torrents, the menu
bar item, the app icon, signing for other Macs, a Forgejo remote (Dan
creates `dan/umbra-macos` when he wants it pushed).
