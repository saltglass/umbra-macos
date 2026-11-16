import Foundation
import HTTPTypes
import Testing
import UmbraAPI

@testable import UmbraKit

@Suite struct ConnectionTests {
  let base = URL(string: "http://127.0.0.1:7979")!

  @Test func launchTokenIsSentInItsOwnHeader() async throws {
    let transport = FakeTransport()
    let client = Connection(baseURL: base, credential: .launchToken("tok-123"))
      .makeClient(transport: transport)
    _ = try await client.ssoUnlink()
    let request = try #require(await transport.requests.first)
    #expect(request.headerFields[HTTPField.Name("X-Umbra-Launch-Token")!] == "tok-123")
    #expect(request.headerFields[HTTPField.Name("X-Api-Key")!] == nil)
  }

  @Test func apiKeyIsSentInItsOwnHeader() async throws {
    let transport = FakeTransport()
    let client = Connection(baseURL: base, credential: .apiKey("key-456"))
      .makeClient(transport: transport)
    _ = try await client.ssoUnlink()
    let request = try #require(await transport.requests.first)
    #expect(request.headerFields[HTTPField.Name("X-Api-Key")!] == "key-456")
    #expect(request.headerFields[HTTPField.Name("X-Umbra-Launch-Token")!] == nil)
  }

  @Test func serverURLAddsApiPath() {
    let plain = Connection(baseURL: base, credential: .apiKey("k"))
    #expect(plain.serverURL.absoluteString == "http://127.0.0.1:7979/api/v1")
  }

  @Test func serverURLIgnoresTrailingSlash() {
    let url = URL(string: "http://127.0.0.1:7979/")!
    let connection = Connection(baseURL: url, credential: .apiKey("k"))
    #expect(connection.serverURL.absoluteString == "http://127.0.0.1:7979/api/v1")
  }

  @Test func serverURLKeepsPathPrefix() {
    for text in ["https://nas.local/umbra", "https://nas.local/umbra/"] {
      let connection = Connection(baseURL: URL(string: text)!, credential: .apiKey("k"))
      #expect(connection.serverURL.absoluteString == "https://nas.local/umbra/api/v1")
    }
  }

  @Test func printingNeverShowsTheCredential() {
    let connection = Connection(baseURL: base, credential: .launchToken("super-secret"))
    #expect(!"\(connection)".contains("super-secret"))
    #expect(!String(reflecting: connection).contains("super-secret"))
  }

  /// Umbra (Go) writes times to the nanosecond, or with no fraction on a
  /// whole second; the generated client must read both.
  @Test func generatedClientReadsGoTimes() async throws {
    let json = """
      {"state":"connected","configured":true,"saved":[],"failover":{"enabled":false,"minutes":5},\
      "lastHandshake":"2026-11-12T15:02:31.123456789Z","since":"2026-11-12T15:02:31Z",\
      "checkedAt":"2026-11-12T15:02:31.5Z"}
      """
    let transport = FakeTransport(status: .ok, json: json)
    let client = Connection(baseURL: base, credential: .apiKey("k")).makeClient(
      transport: transport)
    let vpn = try await client.getVpn().ok.body.json
    let whole = 1_794_495_751.0  // 2026-11-12T15:02:31Z
    #expect(try abs(#require(vpn.lastHandshake).timeIntervalSince1970 - (whole + 0.123)) < 0.001)
    #expect(vpn.since?.timeIntervalSince1970 == whole)
    #expect(try abs(#require(vpn.checkedAt).timeIntervalSince1970 - (whole + 0.5)) < 0.001)
  }

  @Test func sharedDateReaderRejectsNonsense() {
    #expect(UmbraDates.parse("yesterday") == nil)
    #expect(throws: (any Error).self) { try UmbraDateTranscoder().decode("2026-13-45") }
    let date = Date(timeIntervalSince1970: 1_794_495_751.25)
    #expect(UmbraDates.parse(UmbraDates.format(date)) == date)
  }
}
