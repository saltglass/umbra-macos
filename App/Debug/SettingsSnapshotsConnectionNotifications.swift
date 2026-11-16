#if DEBUG
  import SwiftUI
  import UmbraAPI
  import UmbraKit

  /// Pictures of the Connection and Notifications pages. Everything here is
  /// made up (example.com addresses); no password appears anywhere, only
  /// whether one is "Set".
  @MainActor
  enum SettingsSnapshotsConnectionNotifications {
    static let size = CGSize(width: SettingsMetrics.width, height: 560)
    /// Tall enough for the whole Notifications page.
    static let tall = CGSize(width: SettingsMetrics.width, height: 1020)

    static func mail(
      passwordSet: Bool, enabled: Bool = true, host: String = "smtp.example.com"
    ) -> NotificationsDraft {
      NotificationsDraft(
        .init(
          enabled: enabled, host: host, port: 587, security: .starttls,
          username: "umbra@example.com", passwordSet: passwordSet, from: "umbra@example.com",
          to: "you@example.com", onFinished: true, onError: true, onVpn: false,
          onLowDisk: true))
    }

    static func notifications(
      _ draft: NotificationsDraft, refusal: UmbraError? = nil,
      test: NotificationTestModel = .init()
    ) -> AnyView {
      AnyView(
        NotificationsPage(
          model: .init(.notifications, fixture: draft, refusal: refusal), test: test))
    }

    static var entries: [SnapshotEntry] {
      [
        SnapshotEntry(name: "settings-connection", size: size) {
          AnyView(
            ConnectionPage(
              model: .init(.connection, fixture: .init(listenPort: 51413, dht: true, pex: false))))
        },
        // Umbra has just refused the port.
        SnapshotEntry(name: "settings-connection-refused", size: size) {
          AnyView(
            ConnectionPage(
              model: .init(
                .connection, fixture: .init(listenPort: 6881, dht: true, pex: true),
                refusal: UmbraError(
                  code: "invalid", message: "Some fields need attention.",
                  fields: ["listenPort": "Enter a port from 1024 to 65535."]))))
        },
        SnapshotEntry(
          name: "settings-connection-not-connected",
          size: CGSize(width: SettingsMetrics.width, height: 300)
        ) {
          AnyView(ConnectionPage(model: .init(.connection, fixture: nil, phase: .notConnected)))
        },
        // A password is stored, and a test email has just gone through.
        SnapshotEntry(name: "settings-notifications-set-sent", size: tall) {
          notifications(mail(passwordSet: true), test: .init(fixture: .sent))
        },
        // No password, Umbra refused a field, and the test failed.
        SnapshotEntry(name: "settings-notifications-not-set-refused", size: tall) {
          notifications(
            mail(passwordSet: false, host: "smtp.example"),
            refusal: UmbraError(
              code: "invalid", message: "Some fields need attention.",
              fields: ["host": "Enter the mail server's name, like smtp.example.com."]),
            test: .init(
              fixture: .failed(
                message: "The mail server at smtp.example.com refused the password.")))
        },
        SnapshotEntry(name: "settings-notifications-sending", size: tall) {
          notifications(mail(passwordSet: true), test: .init(fixture: .sending))
        },
        // Email still off and nothing filled in yet: the Send button waits.
        SnapshotEntry(name: "settings-notifications-empty", size: tall) {
          notifications(
            NotificationsDraft(
              .init(
                enabled: false, host: "", port: 587, security: .starttls, username: "",
                passwordSet: false, from: "", to: "", onFinished: true, onError: true,
                onVpn: true, onLowDisk: true)))
        },
        SnapshotEntry(
          name: "settings-notifications-not-connected",
          size: CGSize(width: SettingsMetrics.width, height: 300)
        ) {
          AnyView(
            NotificationsPage(model: .init(.notifications, fixture: nil, phase: .notConnected)))
        },
      ]
    }
  }
#endif
