import Darwin
import Foundation
import Synchronization
import UmbraAPI

/// Gives a test's helper a peer port of its own.
///
/// Every new Umbra listens for peers on port 6881 (its stored default), so
/// a test's helper and the development app's helper, or two tests' helpers,
/// would clash: the second one's engine can't start ("port in use"). Umbra
/// keeps answering when that happens, so once a test's helper is up it is
/// told, through Settings → Connection, to use a port nobody is using; its
/// engine then starts (again) there. No change to Umbra is needed.
enum PeerPort {
  /// Moves the helper at `connection` to a free port and waits until its
  /// engine runs there (the torrent list answers).
  ///
  /// Umbra answers requests a moment before its own first try at starting
  /// the engine (on the stored port). If the new port is saved in that
  /// moment, the first try comes after and uses the old port, fails on a
  /// busy 6881, and nothing tries again. So if the engine isn't running
  /// soon after, another free port is saved, which starts it afresh; by
  /// then the first try is long over. (Seen 2026-11-12 with eight helpers
  /// starting at once; a fix in Umbra would be to start the engine before
  /// answering, but this needs none.)
  static func moveToFreePort(_ connection: Connection) async throws(HelperError) {
    let client = connection.makeClient()
    var tried: [Int] = []
    do {
      for _ in 0..<5 {
        guard let port = freePort() else {
          throw HelperError(message: "No free port for the test helper's peers.", logTail: [])
        }
        tried.append(port)
        let current = try await client.getConnectionSettings().ok.body.json
        let wanted = Components.Schemas.ConnectionSettings(
          listenPort: port, dht: current.dht, pex: current.pex)
        _ = try await client.putConnectionSettings(body: .json(wanted)).ok
        // The engine restarts on the new port a moment after the answer.
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
          if case .ok = try await client.listTorrents() { return }
          try await Task.sleep(for: .milliseconds(20))
        }
      }
      throw HelperError(
        message: "The test helper's engine didn't start on its own peer port (tried \(tried)).",
        logTail: [])
    } catch let error as HelperError {
      throw error
    } catch {
      throw HelperError(
        message: "Couldn't give the test helper its own peer port: \(error.localizedDescription)",
        logTail: [])
    }
  }

  /// A port on 127.0.0.1 that is free for both TCP and UDP right now (peers
  /// use both on the same number).
  ///
  /// It is picked from 20000 to 39999, below the range the system hands out
  /// for "any free port" (49152 and up). Every helper's own web server asks
  /// for "any free port" as it starts, so a port from that range, freed
  /// again after this check, could be given to another helper starting at
  /// the same moment, and the engine would then find it taken. Successive
  /// calls take successive numbers from a random start, so tests running
  /// side by side don't pick the same one.
  static func freePort() -> Int? {
    for _ in 0..<200 {
      let port = next.withLock { value -> UInt16 in
        value = value >= 39_999 ? 20_000 : value + 1
        return value
      }
      if bind(SOCK_STREAM, port: port) != nil, bind(SOCK_DGRAM, port: port) != nil {
        return Int(port)
      }
    }
    return nil
  }

  /// The last port handed out; a Mutex makes it safe to share between tasks.
  private static let next = Mutex<UInt16>(UInt16.random(in: 20_000...39_999))

  /// Binds a socket of `type` to 127.0.0.1:`port` (0: any) and closes it
  /// again; returns the port it got, or nil if it couldn't.
  private static func bind(_ type: Int32, port: UInt16) -> UInt16? {
    let fd = socket(AF_INET, type, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let size = socklen_t(MemoryLayout<sockaddr_in>.size)
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, size) }
    }
    guard bound == 0 else { return nil }
    var actual = sockaddr_in()
    var length = size
    let named = withUnsafeMutablePointer(to: &actual) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
    }
    guard named == 0 else { return nil }
    return UInt16(bigEndian: actual.sin_port)
  }
}
