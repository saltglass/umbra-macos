# Umbra for macOS

A native Mac app for Umbra, Dan's self-hosted BitTorrent client. The Mac
interface is Swift; the backend is the real Umbra server, shipped inside
the app as a helper, so the two keep feature parity.

- Owner: Dan. GPL-3.0 (it bundles Umbra, which is GPL-3.0). Public at
  github.com/saltglass/umbra-macos since 0.1.1 (2026-11-15), with the
  disk image on its releases page, not signed by Apple. Dan expects to be its only
  user and pays for an Apple Developer account only if that changes.
- Dan is not a developer. Claude writes nearly all of the code, so the
  code, tests and docs must explain themselves.
- **Status:** planned 2026-11-12. `PLAN.md` is the plan. **M0, the
  foundation, done 2026-11-12** (docs/m0-plan.md). **M1, the main
  window, done 2026-11-13** (docs/m1-plan.md): list, sidebar, inspector,
  menus, Add, Remove, the VPN pill and banners, checked by Dan on
  `just demo`. **M2, Settings, done 2026-11-13** (docs/m2-plan.md): six pages
  including VPN; the real app holds every torrent until a VPN is set up
  or "Start without VPN" is chosen. Dan checked it on `just demo`, then
  ran the Release app with his own VPN and downloaded a torrent through
  it. **M3, Mac integration, built 2026-11-14**
  (docs/m3-plan.md): opening files and links, the menu bar item,
  notifications, keep awake, open at login, and re-checking the VPN on
  wake. Dan passed the checkpoint 2026-11-14, apart from an overnight
  sleep he hasn't tried yet; reconnecting after wake took about half a
  minute and was made quicker in Umbra (9866b79). **M4, the rest of parity, built
  2026-11-14** (docs/m4-plan.md, no web interface): Move, limits, Create
  Torrent, Logs, backup and restore. Checkpoint passed 2026-11-15.
  **M5, release** (docs/m5-plan.md): the icon, About and licences, the
  version (`Config/Version.xcconfig`), hardened mode, `just dist` and
  the README built 2026-11-14. Dan dropped the signed, public release
  on 2026-11-15: 0.1.1 is private and unsigned. **Done 2026-11-15:**
  Dan installed it from the disk image ("Looks good"); tagged `v0.1.1`.
  v1 (M0 to M5) is complete. The source went to GitHub the same day.
- Umbra itself is in `~/Forgejo/umbra` (public at
  github.com/saltglass/umbra). Read its `CLAUDE.md` before touching
  anything that talks to the engine: its rules apply here too.
- Dan's own setup goes in the git-ignored `CLAUDE.local.md`. Nothing
  private goes in this file.

## Product principles

Umbra's, plus:

- **Umbra is the backend, always.** No torrent, VPN, queue or settings
  logic in Swift. If the app needs something Umbra's API doesn't give,
  the change is made in Umbra first (API, tests, web page if it applies),
  then used here.
- **Never a setting Umbra doesn't have.** Where the design canvas and
  Umbra disagree, Umbra wins and the canvas is corrected.
- **A Mac app, not a web page in a window.** System controls, menus,
  sheets, shortcuts, light and dark, the system accent colour. Follow
  Apple's conventions before inventing anything.
- **Private by default.** The helper answers only on 127.0.0.1, only to
  the app that started it. Nothing ever listens on the network: no web
  interface for other devices (Dan, 2026-11-14; Umbra in Docker is for
  that).
- **Safe by default**, as Umbra: never outside the VPN when one is set,
  never delete data without saying so first.

## Scope

- **v1 (M0 to M5):** see PLAN.md.
- **Later:** remote control of an Umbra on another machine, running with
  no app open, Intel Macs, updating itself.
- **Non-goals:** the Mac App Store, the App Sandbox (the helper must
  write to any folder the person chooses), iOS, a second engine,
  anything Umbra lists as a non-goal.

## Stack

- **Swift 6, SwiftUI** for the app's structure (windows, Settings, menu
  bar item, sheets), AppKit where SwiftUI falls short. Swift because it
  is the only route to real Mac windows and menus.
- **macOS 26 or newer, Apple silicon only.** Dan has no Intel Mac to
  test on, and Umbra's lesson is that ARM passing proves nothing for
  Intel.
- **The helper:** Umbra's own binary, built from the version named in
  `UMBRA_VERSION`, placed inside the app. Never patched here.
- **API code:** generated from Umbra's `api/openapi.yaml` (of the pinned
  version) with Apple's swift-openapi-generator. Never hand-edit
  generated code.
- **Live updates:** Umbra's Server-Sent Events stream.
- **Project file:** generated from `project.yml` by XcodeGen, because an
  Xcode project can't sensibly be written or reviewed by hand. The
  `.xcodeproj` is not committed.
- **Logic lives in the `UmbraKit` Swift package** (API code, live feed,
  helper supervision, models), tested with `swift test`. The app target
  holds views only.
- **Tooling:** `just`, swift-format, Swift Testing.

## Core design

- **One connection type for everything:** an address plus a credential.
  The bundled helper is one (127.0.0.1 and the launch token); a
  development server is another; remote control later is a third. Views
  never know which.
- **The launch token** is random, made at every launch, handed to the
  helper when it starts, never written to disk or logged.
- **The helper's life is the app's life.** Started at launch; restarted
  if it crashes (with a plain message after repeated failures); told to
  stop at Quit, and waited for while the engine saves. Closing the
  window does not quit: torrents carry on, with the menu bar item
  showing. Quit stops them.
- **Data folder:** `~/Library/Application Support/Umbra`. Development
  builds use a different one and can never open the real one.
- **The secret key** stays in Umbra's data folder as in the Docker
  version (Dan, 2026-11-14: not the Keychain for 0.1.1).

## Working rules for Claude

- **Fable plans; Opus and Sonnet build** (Dan, 2026-11-12). The planning
  model writes each milestone's plan, splits it into tasks, hands each
  to a subagent, then reviews the result and runs the checks itself
  before calling anything done.
  - **Opus:** anything subtle or risky: changes inside Umbra (auth
    above all), helper supervision, the live feed, concurrency, sleep
    and wake, signing.
  - **Sonnet:** well-specified work: scaffolding, a screen built to a
    board of the canvas, tying a settings page to its API calls, tests
    for settled behaviour, docs.
  - **Effort** (Dan, 2026-11-12): Opus subagents run at medium effort,
    Sonnet subagents at high.
  - Every task handed over names its files, the behaviour wanted, the
    tests that prove it, and what not to touch.
- **Explain in plain English.** Before each milestone, a short plan with
  its size (small / medium / large, and why) and Dan's OK. Afterwards,
  what changed and how to see it working.
- **Tests alongside the code.** `just lint` and `just test` pass before
  anything is called done.
- **Never touch real services from tests or development:** no real
  trackers, no public swarms, no real VPN provider, not Dan's Umbra on
  the server. Development helpers run with `UMBRA_LOOPBACK_ONLY=true`.
- **Changes to Umbra** are made in `~/Forgejo/umbra` under its own rules
  (its tests, its lint, its `next` branch), never by patching the helper
  here.
- **Dependencies:** prefer Apple's frameworks; a new dependency needs a
  stated reason in the commit message.
- **Commits:** small, conventional (`feat:`, `fix:`, ...). In this repo,
  commit each step once Fable has verified it, before the next subagent
  starts (Dan, 2026-11-12), and push it to Forgejo. Subagents never
  commit. Changes in the `umbra` repo are committed and pushed only
  when Dan asks. `.githooks/pre-push` runs lint and the tests before
  every push (turn on with `git config core.hooksPath .githooks`).
- **Check visual changes at device scale 1**, dark and light, against
  the canvas.

## Decisions (2026-11-12, Dan)

- Native interface, Umbra as the backend, shipped inside the app.
- Local only for now; built so remote control can be added.
- Private on Forgejo first; public release and the Apple Developer
  account ($99 a year) decided at M5. (Decided 2026-11-15: neither, for
  now.)
- GPL-3.0.
- Apple silicon, macOS 26 or newer.
- Closing the window leaves torrents running in the menu bar; Quit
  stops them.
- No updating itself at first: new versions are downloaded by hand.
- The design canvas is corrected to match Umbra before M2.
- Fable plans and delegates the work to Opus or Sonnet.
- **As native as possible:** the system's colours, materials, controls,
  accent and SF Symbols; no colours of Umbra's own. The canvas gives
  layout and wording only.
- Built and measured for 100 torrents, not thousands.
- Removing with files deletes them (Umbra does it); no Trash for now.
- The list's columns and sort are remembered on this Mac, not in
  Umbra's shared preferences.

## Decisions (2026-11-13, Dan), for Settings (M2)

- Settings apply as they're changed; no Save button. A refused value
  goes back to what it was and says why.
- A VPN configuration goes straight to Umbra and is never kept, logged
  or drawn by the Mac app.
- "Start without VPN" always asks first and says peers will see this
  Mac's real address.
- The first real run uses the real data folder, in a Release build.
- On first launch the Mac app holds everything until a VPN is set up or
  the person chooses "Start without VPN": nothing touches the network
  before that. (Umbra by itself runs without a VPN until one is added;
  the app turns on an opt-in Umbra setting for this.)
