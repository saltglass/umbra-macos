import Foundation
import UmbraAPI

/// The words in the bottom status bar, mirroring the web page's status bar
/// (`web/src/components/shell/StatusBar.tsx`). Almost everything comes from
/// the live feed's "transfer" totals; the port comes from Settings →
/// Connection (or the VPN's forwarded port), which `AppSession` asks for
/// now and then.
public struct StatusBarInfo: Equatable, Sendable {
  /// "412 GB free"; nil until Umbra has said (or if it can't tell).
  public let freeSpace: String?
  /// Whether peers have connected in recently (never a guess from outside).
  public let incomingWorks: Bool
  /// "Incoming connections: working" or "No incoming connections yet".
  public let incoming: String
  /// "Port 6881": the port peers connect to; nil until known.
  public let port: String?
  /// "DHT: 1,204 nodes".
  public let dht: String
  /// "8.4 MB/s" and "1.2 MB/s": the total speeds now.
  public let down: String
  public let up: String
  /// "This session: 31.0 GB down, 4.2 GB up" (shown on hover).
  public let session: String
  /// What's wrong with the live feed, if anything ("Reconnecting…").
  public let feedNote: String?

  public init(
    transfer: Components.Schemas.Transfer?, connection: FeedConnectionState,
    listenPort: Int?, vpn: Components.Schemas.VpnStatus?, locale: Locale = .current
  ) {
    let t = transfer
    freeSpace = t.flatMap { $0.freeSpace >= 0 ? "\(Format.bytes($0.freeSpace)) free" : nil }
    incomingWorks = t?.incoming ?? false
    incoming = incomingWorks ? "Incoming connections: working" : "No incoming connections yet"
    port = Self.peerPort(listenPort: listenPort, vpn: vpn).map { "Port \($0)" }
    dht =
      t.map { "DHT: \(Format.count($0.dhtNodes, locale: locale)) nodes" } ?? "DHT: \(Format.dash)"
    down = Format.speed(t?.downSpeed, zero: "0 B/s")
    up = Format.speed(t?.upSpeed, zero: "0 B/s")
    session =
      "This session: \(Format.bytes(t?.sessionDownloaded ?? 0)) down, "
      + "\(Format.bytes(t?.sessionUploaded ?? 0)) up"
    feedNote =
      switch connection {
      case .live: nil
      case .connecting: "Connecting…"
      case .reconnecting: "Reconnecting…"
      case .refused: "Umbra turned the connection away"
      }
  }

  /// The port peers reach Umbra on: through a connected VPN with a
  /// forwarded port, that port; otherwise Umbra's own listening port.
  static func peerPort(listenPort: Int?, vpn: Components.Schemas.VpnStatus?) -> Int? {
    if let vpn, vpn.state == .connected, let forwarded = vpn.forwardedPort, forwarded > 0 {
      return forwarded
    }
    return listenPort
  }
}
