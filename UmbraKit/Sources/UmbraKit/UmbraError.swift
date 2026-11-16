import Foundation
import UmbraAPI

/// What went wrong, in words fit to show the person.
///
/// Umbra answers every failure with a small JSON note holding a stable `code`
/// and a plain-English `message`. This turns that note into a normal Swift error.
public struct UmbraError: Error, Sendable, Equatable, LocalizedError {
  /// Stable machine-readable code such as `invalid_credentials`.
  public let code: String
  /// Plain-English explanation from the server.
  public let message: String
  /// Per-field problems (for forms), keyed by field name.
  public let fields: [String: String]

  public init(code: String, message: String, fields: [String: String] = [:]) {
    self.code = code
    self.message = message
    self.fields = fields
  }

  /// Wraps the server's error note (the `Error` shape in the API description).
  public init(_ error: Components.Schemas._Error) {
    self.init(
      code: error.code,
      message: error.message,
      fields: error.fields?.additionalProperties ?? [:]
    )
  }

  /// Shown by `error.localizedDescription`, so alerts read the server's own words.
  public var errorDescription: String? { message }
}
