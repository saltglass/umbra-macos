import Foundation
import Security

/// The secret code the app hands the helper at every start.
///
/// Any program on this Mac can reach 127.0.0.1, so the helper lets in only
/// requests carrying this code. It is made fresh from the system's secure
/// random source each time, kept only in memory, and never written to disk,
/// logged or shown.
enum LaunchToken {
  /// 32 random bytes as 64 hex characters.
  static func make() throws(HelperError) -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard status == errSecSuccess else {
      throw HelperError(
        message: "The Mac couldn't make a secure random code for Umbra (error \(status)).",
        logTail: [])
    }
    return bytes.map { String(format: "%02x", $0) }.joined()
  }
}
