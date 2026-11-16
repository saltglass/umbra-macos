import Foundation

// Small helpers the Notifications page needs, kept here (not in the view)
// so they can be tested. None of them judges a value: Umbra does that.

/// One way of talking to the mail server, as the web page words it.
public struct MailSecurityChoice: Identifiable, Equatable, Sendable {
  /// Umbra's name for it: "starttls", "tls" or "none".
  public let id: String
  /// What the menu says.
  public let label: String
  /// The port that usually goes with it.
  public let usualPort: Int

  /// In the order the web page lists them.
  public static let all = [
    MailSecurityChoice(id: "starttls", label: "STARTTLS (port 587)", usualPort: 587),
    MailSecurityChoice(id: "tls", label: "TLS (port 465)", usualPort: 465),
    MailSecurityChoice(id: "none", label: "None (a relay with no password)", usualPort: 25),
  ]
}

extension NotificationsDraft {
  /// The choice now selected (Umbra's "security" setting).
  public var security: String { settings.security.rawValue }

  /// Picks how to talk to the mail server. As on the web page, the port
  /// follows the choice, unless it's been set to something unusual:
  /// someone who typed their own port keeps it.
  public mutating func chooseSecurity(_ id: String) {
    guard let new = MailSecurityChoice.all.first(where: { $0.id == id }),
      let value = type(of: settings.security).init(rawValue: new.id)
    else { return }
    let portIsUsual = MailSecurityChoice.all.contains { $0.usualPort == settings.port }
    settings.security = value
    if portIsUsual { settings.port = new.usualPort }
  }

  /// Whether a password is stored, counting one that has just been typed
  /// and is on its way, and not one that has just been removed.
  public var passwordIsSet: Bool {
    switch password {
    case .unchanged: settings.passwordSet
    case .replaced: true
    case .removed: false
    }
  }

  /// Whether a test email can be tried: the three things any email needs
  /// are filled in (the web page's rule for its Send button). Whether they
  /// are right is for Umbra and the mail server to say.
  public var canSendTest: Bool {
    !settings.host.isEmpty && !settings.from.isEmpty && !settings.to.isEmpty
  }
}
