import Foundation
import Testing
import UmbraAPI

@testable import UmbraKit

@Suite struct UmbraErrorTests {
  @Test func serverErrorBecomesUmbraErrorWithItsMessage() async throws {
    let transport = FakeTransport(
      status: .conflict,
      json:
        #"{"code":"password_login_off","message":"Password sign-in is off.","fields":{"x":"bad"}}"#
    )
    let client = Connection(
      baseURL: URL(string: "http://127.0.0.1:1")!, credential: .apiKey("k")
    ).makeClient(transport: transport)

    let output = try await client.ssoUnlink()
    guard case .conflict(let response) = output else {
      Issue.record("expected a 409 answer, got \(output)")
      return
    }
    let error = UmbraError(try response.body.json)
    #expect(error.code == "password_login_off")
    #expect(error.message == "Password sign-in is off.")
    #expect(error.fields == ["x": "bad"])
    #expect(error.localizedDescription == "Password sign-in is off.")
  }
}
