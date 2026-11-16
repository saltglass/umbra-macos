import Foundation
import HTTPTypes
import Testing
import UmbraAPI

@testable import UmbraKit

/// The Notifications page's logic: the test email (over a fake transport
/// only: no mail server is ever contacted), the small helpers, and the
/// rule that a typed password is sent once and kept nowhere.
@MainActor @Suite struct NotificationsPageTests {
  static let connection = Connection(
    baseURL: URL(string: "http://127.0.0.1:7980")!, credential: .apiKey("key"))

  nonisolated static func settings(
    port: Int = 587, security: Components.Schemas.NotificationsSettings.securityPayload = .starttls,
    passwordSet: Bool = true, host: String = "smtp.example.com"
  ) -> Components.Schemas.NotificationsSettings {
    .init(
      enabled: true, host: host, port: port, security: security, username: "me@example.com",
      passwordSet: passwordSet, from: "umbra@example.com", to: "you@example.com",
      onFinished: true, onError: false, onVpn: true, onLowDisk: false)
  }

  static let storedJSON = """
    {"enabled":true,"host":"smtp.example.com","port":587,"security":"starttls",\
    "username":"me@example.com","passwordSet":true,"from":"umbra@example.com",\
    "to":"you@example.com","onFinished":true,"onError":false,"onVpn":true,"onLowDisk":false}
    """

  func actions(_ replies: [String: RecordingTransport.Reply]) -> (
    SettingsActions, RecordingTransport
  ) {
    let transport = RecordingTransport(replies)
    return (SettingsActions(connection: Self.connection, transport: transport), transport)
  }

  // MARK: The test email

  @Test func aTestEmailPostsTheSettingsAndSaysSent() async throws {
    let (actions, transport) = actions(["testNotifications": .init()])  // 204
    let model = NotificationTestModel()
    #expect(model.state == .idle)
    model.send(NotificationsDraft(Self.settings()), using: actions)
    #expect(model.state == .sending)
    #expect(await eventually { model.state == .sent })

    let sent = await transport.sent
    #expect(sent.map(\.operation) == ["testNotifications"])
    #expect(sent[0].method == .post)
    #expect(sent[0].path == "/settings/notifications/test")
    #expect(sent[0].json?["host"] as? String == "smtp.example.com")
    // A password left alone isn't sent: Umbra uses the stored one.
    #expect(sent[0].json?["password"] == nil)
    #expect(sent[0].json?["passwordSet"] == nil)
  }

  @Test func aTestEmailCarriesAPasswordTypedButNotYetSaved() async throws {
    let (actions, transport) = actions(["testNotifications": .init()])
    var draft = NotificationsDraft(Self.settings(passwordSet: false))
    draft.password = .replaced("hunter2")
    let model = NotificationTestModel()
    model.send(draft, using: actions)
    #expect(await eventually { model.state == .sent })
    #expect(await transport.sent[0].json?["password"] as? String == "hunter2")
    // Nothing the model keeps holds it.
    #expect(!String(describing: model).contains("hunter2"))
    #expect(!dumped(model).contains("hunter2"))
  }

  @Test func theMailServersRefusalIsShownInUmbrasWords() async {
    let why = "The mail server at smtp.example.com refused the password."
    let (actions, _) = actions([
      "testNotifications": .error(.badGateway, code: "mail_failed", message: why)
    ])
    let model = NotificationTestModel()
    model.send(NotificationsDraft(Self.settings()), using: actions)
    #expect(await eventually { model.state == .failed(message: why) })
    #expect(!model.isSending)
  }

  @Test func settingsUmbraWontAcceptAreNamedInTheMessage() async {
    let refusal = RecordingTransport.Reply.json(
      #"{"code":"invalid","message":"Some fields need attention.","fields":{"host":"Enter the mail server's name."}}"#,
      status: .unprocessableContent)
    let (actions, _) = actions(["testNotifications": refusal])
    let model = NotificationTestModel()
    model.send(NotificationsDraft(Self.settings(host: "")), using: actions)
    #expect(await eventually { model.state == .failed(message: "Enter the mail server's name.") })
  }

  @Test func notConnectedSaysSoAndASecondClickWhileSendingDoesNothing() async {
    let model = NotificationTestModel()
    model.send(NotificationsDraft(Self.settings()), using: nil)
    #expect(model.state == .failed(message: "Umbra isn't running, so a test can't be sent."))

    let (actions, transport) = actions(["testNotifications": .init()])
    model.send(NotificationsDraft(Self.settings()), using: actions)
    model.send(NotificationsDraft(Self.settings()), using: actions)  // ignored
    #expect(await eventually { model.state == .sent })
    #expect(await transport.sent.count == 1)

    // Changed settings make the old answer meaningless.
    model.clear()
    #expect(model.state == .idle)
  }

  @Test func clearingLeavesATestOnItsWayAlone() {
    let model = NotificationTestModel(fixture: .sending)
    model.clear()
    #expect(model.state == .sending)
  }

  // MARK: Helpers

  @Test func choosingSecurityMovesAUsualPortButKeepsAnUnusualOne() {
    var draft = NotificationsDraft(Self.settings(port: 587))
    draft.chooseSecurity("tls")
    #expect(draft.security == "tls" && draft.settings.port == 465)
    draft.chooseSecurity("none")
    #expect(draft.security == "none" && draft.settings.port == 25)

    var custom = NotificationsDraft(Self.settings(port: 2525))
    custom.chooseSecurity("tls")
    #expect(custom.security == "tls" && custom.settings.port == 2525)

    // A name Umbra doesn't have changes nothing.
    custom.chooseSecurity("ssl3")
    #expect(custom.security == "tls")
  }

  @Test func securityMenuWordingFollowsTheWebPage() {
    #expect(
      MailSecurityChoice.all.map(\.label) == [
        "STARTTLS (port 587)", "TLS (port 465)", "None (a relay with no password)",
      ])
    // Every choice is one Umbra knows.
    for choice in MailSecurityChoice.all {
      #expect(Components.Schemas.NotificationsSettings.securityPayload(rawValue: choice.id) != nil)
    }
  }

  @Test func thePasswordShowsAsSetUntilItIsRemoved() {
    var draft = NotificationsDraft(Self.settings(passwordSet: true))
    #expect(draft.passwordIsSet)
    draft.password = .removed
    #expect(!draft.passwordIsSet)
    var none = NotificationsDraft(Self.settings(passwordSet: false))
    #expect(!none.passwordIsSet)
    none.password = .replaced("x")
    #expect(none.passwordIsSet)
  }

  @Test func aTestNeedsAServerAndBothAddresses() {
    #expect(NotificationsDraft(Self.settings()).canSendTest)
    #expect(!NotificationsDraft(Self.settings(host: "")).canSendTest)
    var draft = NotificationsDraft(Self.settings())
    draft.settings.to = ""
    #expect(!draft.canSendTest)
  }

  // MARK: A typed password

  /// Typed and committed through the page's own path, over a fake
  /// transport and Umbra's real notifications group.
  @Test func aTypedPasswordIsSentOnceAndKeptNowhere() async throws {
    let (actions, transport) = actions([
      "getNotificationsSettings": .json(Self.storedJSON),
      "putNotificationsSettings": .json(Self.storedJSON),
    ])
    let source = FakeSettingsSource(connected: false)
    source.settingsActions = actions
    let model = SettingsGroupModel(.notifications, source: source)
    #expect(await eventually { model.phase == .loaded })

    let secret = SettingsFormat<SecretChange>.newSecret
    model.type("hunter2", into: \.password)
    // Nothing is sent while it's being typed.
    #expect(await transport.sent.filter { $0.operation.hasPrefix("put") }.isEmpty)
    model.commit(\.password, as: secret)
    #expect(await eventually { await transport.sent.contains { $0.operation.hasPrefix("put") } })
    #expect(await eventually { !model.isSending })

    // The field empties; the page shows "Set"; Umbra's answer holds no secret.
    #expect(model.text(\.password, as: secret) == "")
    #expect(!model.isTyping(in: \.password))
    #expect(model.value?.password == .unchanged)
    #expect(model.value?.passwordIsSet == true)

    // Not in what the model prints or holds.
    #expect(!String(describing: model).contains("hunter2"))
    #expect(!String(reflecting: model).contains("hunter2"))
    // (The fake transport keeps every request it's sent, so only what
    // the model itself holds is dumped here; the next test dumps the
    // whole model against a fake that keeps nothing.)
    #expect(!dumped(model.value as Any).contains("hunter2"))

    // A later change doesn't send it again.
    model.set(\.settings.onVpn, to: false)
    #expect(
      await eventually { await transport.sent.filter { $0.operation.hasPrefix("put") }.count == 2 })
    let puts = await transport.sent.filter { $0.operation.hasPrefix("put") }
    #expect(puts.filter { $0.body.contains("hunter2") }.count == 1)
    #expect(puts[0].json?["password"] as? String == "hunter2")
    #expect(puts[1].json?["password"] == nil)
  }

  /// A pretend Umbra for the notifications group that notes only whether
  /// a password arrived, never what it was.
  actor PasswordBlindServer {
    private(set) var passwordsReceived = 0
    private let stored = NotificationsDraft(NotificationsPageTests.settings())

    func write(_ draft: NotificationsDraft) -> NotificationsDraft {
      if draft.password != .unchanged { passwordsReceived += 1 }
      return stored
    }

    nonisolated var group: SettingsGroup<NotificationsDraft> {
      SettingsGroup(
        name: "notifications",
        read: { _ async throws(UmbraError) in NotificationsDraft(NotificationsPageTests.settings())
        },
        write: { draft, _ async throws(UmbraError) in await self.write(draft) })
    }
  }

  @Test func theWholeModelHoldsNoPasswordBeforeOrAfterItIsSent() async {
    let server = PasswordBlindServer()
    let model = SettingsGroupModel(server.group, source: FakeSettingsSource())
    #expect(await eventually { model.phase == .loaded })
    let secret = SettingsFormat<SecretChange>.newSecret

    model.type("hunter2", into: \.password)
    // While it is being typed it is held (and the dump can see it, so
    // the check below is not vacuous)...
    #expect(dumped(model).contains("hunter2"))
    // ...and committing sends it and lets go of it.
    model.commit(\.password, as: secret)
    #expect(await eventually { await server.passwordsReceived == 1 })
    #expect(await eventually { !model.isSending })
    #expect(!dumped(model).contains("hunter2"))
    #expect(!String(reflecting: model).contains("hunter2"))
    #expect(await server.passwordsReceived == 1)  // once, not again
  }

  @Test func removingThePasswordSendsAnEmptyOne() async throws {
    let (actions, transport) = actions([
      "getNotificationsSettings": .json(Self.storedJSON),
      "putNotificationsSettings": .json(Self.storedJSON),
    ])
    let source = FakeSettingsSource(connected: false)
    source.settingsActions = actions
    let model = SettingsGroupModel(.notifications, source: source)
    #expect(await eventually { model.phase == .loaded })
    model.set(\.password, to: .removed)
    #expect(await eventually { await transport.sent.contains { $0.operation.hasPrefix("put") } })
    #expect(await transport.sent.last?.json?["password"] as? String == "")
  }

  /// Everything `dump` shows of a value.
  func dumped(_ value: Any) -> String {
    var text = ""
    dump(value, to: &text)
    return text
  }
}
