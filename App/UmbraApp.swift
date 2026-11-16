// Umbra for macOS: the app's entry point.
//
// At launch the app starts its bundled Umbra server (the "helper", in
// Umbra.app/Contents/Helpers/umbra) and shows its torrents. Closing the
// window leaves it running; Quit stops the helper, waiting while it saves.
//
// DEVELOPMENT: attaching to a running Umbra instead of the helper.
// In Debug builds only, if both of these are set, no helper is started and
// the app connects to that server with an API key:
//
//   UMBRA_DEV_ATTACH_URL   the server's address, e.g. http://127.0.0.1:7980
//   UMBRA_DEV_ATTACH_KEY   an API key made in that server's settings
//
// For example, with `just demo` running in ~/Forgejo/umbra (it serves on
// port 7980): make an API key in its web page (Settings), then
//
//   UMBRA_DEV_ATTACH_URL=http://127.0.0.1:7980 UMBRA_DEV_ATTACH_KEY=<key> \
//     build/DerivedData/Build/Products/Debug/Umbra.app/Contents/MacOS/Umbra
//
// (`open` doesn't pass environment variables on, so run the program inside
// the app directly.)
//
// DEVELOPMENT: the stress feed. In Debug builds only, UMBRA_DEV_STRESS=1
// starts no helper and shows 100 made-up torrents that change every second
// (see StressFeed in UmbraKit). UMBRA_DEV_STRESS_SEED picks another list.
//
// The program's real starting point is Launcher.swift, which can also draw
// pictures of the views instead of opening the app (`just snapshot`).

import AppKit
import SwiftUI
import UmbraKit

struct UmbraApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Window("Umbra", id: "main") {
      MainWindow(session: appDelegate.session, model: appDelegate.model)
        .environment(\.torrentCommands, appDelegate.torrentCommands)
        .environment(\.addTorrents, appDelegate.addTorrents)
        .frame(minWidth: 760, minHeight: 420)
        // So files and links opened from outside can bring this window forward.
        .modifier(MainWindowOpener(presenter: appDelegate.addTorrents))
    }
    .defaultSize(width: 1160, height: 720)
    .commands {
      MainCommands(model: appDelegate.model)
      TorrentMenuCommands(model: appDelegate.model, runner: appDelegate.torrentCommands)
      AddCommands(presenter: appDelegate.addTorrents)
      AboutCommands()
    }

    // The menu bar item and its panel (see App/MenuBar).
    MenuBarScene(model: appDelegate.torrentCommands.menuBar)

    // --- Logs window (Window → Logs, ⌥⌘L; see App/Logs) ---
    Window("Logs", id: "logs") { LogsWindow(session: appDelegate.session) }
      .defaultSize(width: 820, height: 480)
      .keyboardShortcut("l", modifiers: [.command, .option])
    // --- end of the Logs window's block ---

    // --- About Umbra window and its Licences… window (see App/About) ---
    Window("About \(AboutInfo(infoDictionary: Bundle.main.infoDictionary).name)", id: "about") {
      AboutWindow(session: appDelegate.session)
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
    .windowBackgroundDragBehavior(.enabled)
    .defaultPosition(.center)
    Window("Licences", id: "licences") { LicencesWindow() }
      .defaultSize(width: 720, height: 520)
    // --- end of the About block ---

    // macOS's own settings window: ⌘, and Umbra → Settings… open it.
    Settings {
      SettingsWindow(models: appDelegate.settings, general: appDelegate.general)
        // For one-off requests such as the Notifications page's test email.
        .environment(\.settingsSource, appDelegate.session)
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let session = AppDelegate.makeSession()
  /// What the main window shows (filter, sort, selection...), remembered
  /// across launches in the app's own settings.
  lazy var model = MainWindowModel(store: session.store)
  /// Carries out the torrent menu, toolbar and keyboard actions.
  lazy var torrentCommands = TorrentCommandRunner(session: session, model: model)
  /// One model per settings group, for the Settings window's pages.
  lazy var settings = SettingsModels(source: session)
  /// Opens the Add sheet (toolbar and File menu).
  lazy var addTorrents = AddTorrentPresenter(session: session, window: model)

  // MARK: Notifications, keeping the Mac awake, General settings
  // (a block of its own: the logic is in UmbraKit; these are the Mac's parts)

  lazy var notificationService = UserNotificationService()
  /// What Settings → General shows; the switches are shared with the two below.
  // Backup (M4): the session also makes and restores backups.
  lazy var general = GeneralSettings(
    notificationService: notificationService, backupSource: session)
  lazy var notifier = NotificationCoordinator(
    session: session, preferences: general.notifications)
  lazy var keepAwake = KeepAwakeController(session: session, preferences: general.keepAwake)

  /// Starts the notifications and the keep-awake hold. Called once at launch.
  private func startGeneralFeatures() {
    notificationService.attach()
    notificationService.onClick = { [weak self] hash in
      guard let self else { return }
      // Opens the window again if it was closed.
      addTorrents.showMainWindow()
      if let hash { model.selectWhenListed([hash]) }
    }
    #if DEBUG
      // The made-up torrents of the stress feed must never reach macOS's notifications.
      let stressing = DevStress.source(from: ProcessInfo.processInfo.environment) != nil
    #else
      let stressing = false
    #endif
    if !stressing { notifier.start() }
    keepAwake.start()
  }

  private static func makeSession() -> AppSession {
    #if DEBUG
      if let stress = DevStress.source(from: ProcessInfo.processInfo.environment) {
        return AppSession(attachingTo: DevStress.connection, feedSource: stress)
      }
      if let attach = DevAttach.connection(from: ProcessInfo.processInfo.environment) {
        return AppSession(attachingTo: attach)
      }
      // Development builds use their own data folder and never reach beyond 127.0.0.1.
      let environment = HelperEnvironment.development()
    #else
      let environment = HelperEnvironment.release()
    #endif
    let helper = Bundle.main.bundleURL.appending(path: "Contents/Helpers/umbra")
    return AppSession(supervisor: HelperSupervisor(executable: helper, environment: environment))
  }

  /// Another copy of Umbra that was already running when this one started.
  /// This copy then does nothing but pass on what it was asked to open.
  private var runningCopy: NSRunningApplication?
  private var handingOver = false

  func applicationWillFinishLaunching(_ notification: Notification) {
    // Only one Umbra at a time: two would fight over the same data folder.
    // A second copy brings the first to the front and leaves (see
    // applicationDidFinishLaunching). macOS can start a second copy when a
    // torrent file is double-clicked and it knows the app in two places.
    let me = NSRunningApplication.current
    if let bundleID = Bundle.main.bundleIdentifier {
      runningCopy = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .first(where: { $0.processIdentifier != me.processIdentifier })
    }
  }

  /// A second copy hands the files or links it was started with to the
  /// copy already running, then leaves. Without this they were lost: Umbra
  /// came to the front and no Add sheet opened.
  private func handOver(_ urls: [URL], to other: NSRunningApplication) {
    guard let app = other.bundleURL else { exit(0) }
    NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: .init()) { _, _ in
      exit(0)
    }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    if let runningCopy {
      // Anything to open has arrived by now (macOS sends it before this).
      runningCopy.activate()
      if !handingOver { exit(0) }
      return
    }
    session.start()
    startGeneralFeatures()
    watchSleepAndWake()  // see the sleep and wake block below
  }

  // --- Sleep and wake: the Mac's own notices, passed on to the session ---
  // The session (WakeRecovery in UmbraKit) decides what to do: show
  // "Checking VPN…", reopen the live feed and ask Umbra about the VPN.
  private var sleepObservers: [NSObjectProtocol] = []

  private func watchSleepAndWake() {
    let center = NSWorkspace.shared.notificationCenter
    let session = session
    sleepObservers = [
      center.addObserver(
        forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
      ) { _ in MainActor.assumeIsolated { session.macWillSleep() } },
      center.addObserver(
        forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
      ) { _ in MainActor.assumeIsolated { session.macDidWake() } },
    ]
  }
  // --- end of the sleep and wake block ---

  // MARK: Files and links opened from outside

  /// .torrent files opened in Umbra (double-click, or dropped on the Dock
  /// icon) and magnet links clicked in a browser. They open the Add sheet;
  /// nothing is added until the person presses Add.
  func application(_ application: NSApplication, open urls: [URL]) {
    if let runningCopy {
      handingOver = true
      handOver(urls, to: runningCopy)
      return
    }
    addTorrents.receive(urls: urls)
  }

  // Closing the window leaves torrents running; only Quit stops them.
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  // --- Menu bar item: clicking the Dock icon brings the window back ---
  // If the window was closed, a click on the Dock icon shows it again. When
  // we can't find it, SwiftUI's own reopening is left to do the work.
  func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows visible: Bool
  ) -> Bool {
    guard !visible,
      let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true })
    else { return true }
    window.makeKeyAndOrderFront(nil)
    return false
  }
  // --- end of the menu bar item's block ---

  private var quitting = false

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    // Quit waits while the helper saves (the window shows "Saving…"), then
    // the app ends. A second Quit while saving just keeps waiting.
    guard !quitting else { return .terminateLater }
    quitting = true
    Task {
      await session.stop()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}
