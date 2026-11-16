import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession
import UmbraAPI

/// Where an Umbra server is and how to prove who we are to it.
///
/// Everything in the app talks to Umbra through one of these, so the views never
/// need to know whether the server is the bundled helper, a development server,
/// or (later) one on another machine.
public struct Connection: Sendable, Equatable {
  /// The proof of identity sent with every request.
  public enum Credential: Sendable, Equatable {
    /// The random code the app hands the bundled helper when it starts it.
    case launchToken(String)
    /// An API key made in Umbra's settings.
    case apiKey(String)

    /// The HTTP header this kind of credential travels in.
    var headerName: HTTPField.Name {
      switch self {
      case .launchToken: HTTPField.Name("X-Umbra-Launch-Token")!
      case .apiKey: HTTPField.Name("X-Api-Key")!
      }
    }

    var secret: String {
      switch self {
      case .launchToken(let value), .apiKey(let value): value
      }
    }
  }

  public var baseURL: URL
  public var credential: Credential

  public init(baseURL: URL, credential: Credential) {
    self.baseURL = baseURL
    self.credential = credential
  }

  /// The address of the API: the base address plus `/api/v1`.
  /// A trailing slash on the base address, or a path prefix in it, both work.
  public var serverURL: URL {
    baseURL.appending(path: "api/v1", directoryHint: .notDirectory)
  }

  /// Makes the generated API client, sending the credential on every request.
  public func makeClient() -> Client {
    makeClient(transport: URLSessionTransport())
  }

  /// Same, over a transport of the caller's choosing (tests pass a fake one so
  /// nothing touches the network).
  public func makeClient(transport: any ClientTransport) -> Client {
    makeClient(transport: transport, extraMiddlewares: [])
  }

  /// Same, with more middlewares after the credential one (the actions
  /// layer adds one that turns error answers into `UmbraError`s).
  func makeClient(transport: any ClientTransport, extraMiddlewares: [any ClientMiddleware])
    -> Client
  {
    Client(
      serverURL: serverURL,
      // Umbra writes times to the nanosecond; the client's standard time
      // reader rejects those, so it uses the same lenient one as the feed.
      configuration: Configuration(dateTranscoder: UmbraDateTranscoder()),
      transport: transport,
      middlewares: [CredentialMiddleware(credential: credential)] + extraMiddlewares
    )
  }
}

// The credential is a secret, so printing a Connection never shows it.
extension Connection: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    "Connection(\(baseURL.absoluteString), credential: <redacted>)"
  }
  public var debugDescription: String { description }
}

/// Adds the credential header to every request the client sends.
struct CredentialMiddleware: ClientMiddleware {
  let credential: Connection.Credential

  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String,
    next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
  ) async throws -> (HTTPResponse, HTTPBody?) {
    var request = request
    request.headerFields[credential.headerName] = credential.secret
    return try await next(request, body, baseURL)
  }
}
