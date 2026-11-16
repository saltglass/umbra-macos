import Foundation

extension Connection {
  /// A plain URLSession request to an API path (such as "events"), carrying
  /// the credential the same way the generated client does (see
  /// `CredentialMiddleware`). For the few calls made outside the generated
  /// client, such as the live feed, which it can't stream.
  ///
  /// The credential is only ever put in the request header; nothing here
  /// prints or logs it.
  func request(path: String) -> URLRequest {
    var request = URLRequest(url: serverURL.appending(path: path, directoryHint: .notDirectory))
    request.setValue(credential.secret, forHTTPHeaderField: credential.headerName.rawName)
    return request
  }
}
