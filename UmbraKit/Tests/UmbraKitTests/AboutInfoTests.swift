import Testing

@testable import UmbraKit

@Suite struct AboutServerLineTests {
  @Test func showsTheVersionOnceTheServerIsRunningAndHasAnswered() {
    #expect(AboutInfo.serverLine(phase: .running, version: "0.4.0") == "Umbra server 0.4.0")
  }

  @Test func dropsALeadingVAndStraySpaces() {
    #expect(AboutInfo.serverLine(phase: .running, version: "v0.4.0") == "Umbra server 0.4.0")
    #expect(AboutInfo.serverLine(phase: .running, version: " 0.4.0\n") == "Umbra server 0.4.0")
    // A development build's version keeps everything else.
    #expect(
      AboutInfo.serverLine(phase: .running, version: "v0.3.0-32-g453d079-dirty")
        == "Umbra server 0.3.0-32-g453d079-dirty")
  }

  @Test func saysNotRunningWhileTheVersionIsNotKnownYet() {
    #expect(AboutInfo.serverLine(phase: .starting, version: nil) == "Umbra server: not running")
    // Running, but Umbra hasn't answered the version question yet.
    #expect(AboutInfo.serverLine(phase: .running, version: nil) == "Umbra server: not running")
    #expect(AboutInfo.serverLine(phase: .running, version: "  ") == "Umbra server: not running")
  }

  @Test func saysNotRunningWhenTheServerFailed() {
    let failed = AppSession.Phase.failed(message: "It stopped.", logTail: [])
    #expect(AboutInfo.serverLine(phase: failed, version: nil) == "Umbra server: not running")
  }

  @Test func doesNotTrustAVersionFromBeforeTheServerStopped() {
    for phase in [
      AppSession.Phase.starting, .reconnecting(attempt: 1), .saving, .stopped,
      .failed(message: "It stopped.", logTail: []),
    ] {
      #expect(AboutInfo.serverLine(phase: phase, version: "0.4.0") == "Umbra server: not running")
    }
  }
}

@Suite struct AboutInfoTests {
  @Test func readsTheAppsNameAndVersions() {
    let info = AboutInfo(infoDictionary: [
      "CFBundleDisplayName": "Umbra Dev", "CFBundleName": "Umbra",
      "CFBundleShortVersionString": "0.1.1", "CFBundleVersion": "7",
    ])
    #expect(info.name == "Umbra Dev")
    #expect(info.versionLine == "Version 0.1.1 (7)")
  }

  @Test func fallsBackToTheBundleNameThenToUmbra() {
    #expect(AboutInfo(infoDictionary: ["CFBundleName": "Umbra"]).name == "Umbra")
    #expect(AboutInfo(infoDictionary: nil).name == "Umbra")
    #expect(AboutInfo(infoDictionary: ["CFBundleDisplayName": ""]).name == "Umbra")
  }

  @Test func wordsAMissingVersionOrBuildPlainly() {
    #expect(
      AboutInfo(name: "Umbra", version: "0.1.1", build: nil).versionLine == "Version 0.1.1")
    #expect(AboutInfo(name: "Umbra", version: nil, build: "7").versionLine == "Version unknown")
  }
}
