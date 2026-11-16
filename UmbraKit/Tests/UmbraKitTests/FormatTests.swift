import Foundation
import Testing

@testable import UmbraKit

/// The cases of Umbra's `web/src/lib/format.test.ts`, one test per case,
/// plus the places where Swift's arithmetic could drift from JavaScript's.
@Suite("format")
struct FormatTests {
  let dash = Format.dash
  let gb: Double = 1024 * 1024 * 1024
  let mb: Double = 1024 * 1024

  @Test("writes sizes as the design does") func writesSizes() {
    #expect(Format.bytes(0) == "0 B")
    #expect(Format.bytes(999) == "999 B")
    #expect(Format.bytes(860 * 1024) == "860 KB")
    #expect(Format.bytes(2.4 * gb) == "2.4 GB")
    #expect(Format.bytes(31 * gb) == "31.0 GB")
    #expect(Format.bytes(734 * mb) == "734 MB")
    #expect(Format.bytes(999.96 * 1024) == "1.0 MB")
    #expect(Format.bytes(nil) == dash)
  }

  @Test("writes speeds, with a dash for nothing") func writesSpeeds() {
    #expect(Format.speed(Int64(8.4 * mb)) == "8.4 MB/s")
    #expect(Format.speed(0) == dash)
    #expect(Format.speed(0, zero: "0 B/s") == "0 B/s")
  }

  @Test("writes ETAs short") func writesETAs() {
    #expect(Format.eta(30) == "30s")
    #expect(Format.eta(41 * 60) == "41m")
    #expect(Format.eta(2 * 3600 + 5 * 60) == "2h 05m")
    #expect(Format.eta(3 * 86400 + 4 * 3600) == "3d 4h")
    #expect(Format.eta(nil as Int64?) == dash)
  }

  @Test("writes ratios and percentages") func writesRatiosAndPercentages() {
    #expect(Format.ratio(2.414) == "2.41")
    #expect(Format.percent(0.999) == "99%")
    #expect(Format.percent(1) == "100%")
  }

  @Test("writes dates relative to today") func writesDatesRelativeToToday() throws {
    let us = Format.DateStyle(
      locale: Locale(identifier: "en_US"), timeZone: try #require(TimeZone(identifier: "UTC")))
    let at = { (y: Int, m: Int, d: Int, h: Int, min: Int) in
      us.calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    let now = at(2026, 10, 29, 15, 0)
    #expect(Format.shortDate(at(2026, 10, 29, 9, 12), now: now, style: us).hasPrefix("Today 9:12"))
    #expect(Format.shortDate(at(2026, 10, 28, 23, 0), now: now, style: us) == "Yesterday")
    #expect(Format.shortDate(at(2026, 10, 26, 0, 0), now: now, style: us).contains("26"))
    #expect(Format.shortDate(at(2025, 10, 26, 0, 0), now: now, style: us).contains("2025"))
    #expect(Format.shortDate(nil, now: now, style: us) == dash)
  }

  // MARK: Beyond the web page's tests

  @Test func datesFollowThePersonsLanguage() throws {
    let gb = Format.DateStyle(
      locale: Locale(identifier: "en_GB"), timeZone: try #require(TimeZone(identifier: "UTC")))
    let at = { (y: Int, m: Int, d: Int, h: Int) in
      gb.calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: 12))!
    }
    let now = at(2026, 10, 29, 15)
    #expect(Format.shortDate(at(2026, 10, 29, 9), now: now, style: gb) == "Today 09:12")
    #expect(Format.shortDate(at(2026, 10, 26, 9), now: now, style: gb) == "26 Oct")
    #expect(Format.shortDate(at(2025, 10, 26, 9), now: now, style: gb) == "26 Oct 2025")
    #expect(Format.longDate(at(2026, 10, 28, 9), style: gb) == "28 Oct 2026, 09:12")
    #expect(Format.longDate(nil, style: gb) == dash)
  }

  @Test func sizesAtTheEdges() {
    #expect(Format.bytes(-1) == dash)
    #expect(Format.bytes(Double.nan) == dash)
    #expect(Format.bytes(1000) == "1 KB")
    #expect(Format.bytes(99.96 * mb) == "100 MB")
    #expect(Format.bytes(5 * gb * 1024 * 1024) == "5.0 PB")
    #expect(Format.bytes(5000 * gb * 1024 * 1024) == "5000 PB")  // no unit above PB
  }

  @Test func timesAtTheEdges() {
    #expect(Format.eta(0) == "1s")  // never "0s": the web page shows at least a second
    #expect(Format.eta(-5) == dash)
    #expect(Format.eta(100 * 86400) == "∞")
    #expect(Format.duration(0) == dash)
    #expect(Format.duration(nil) == dash)
    #expect(Format.duration(42) == "42s")
    #expect(Format.duration(3 * 86400 + 4 * 3600) == "3d 4h")
  }

  @Test func ratiosAtTheEdges() {
    #expect(Format.ratio(nil) == "∞")
    #expect(Format.ratio(.infinity) == "∞")
    #expect(Format.ratio(0) == "0.00")
  }

  @Test func percentagesNeverRoundUpToDone() {
    #expect(Format.percent(0.341) == "34%")
    #expect(Format.percent(0.9999) == "99%")
    #expect(Format.percent(-0.5) == "0%")
    #expect(Format.percent(1.5) == "100%")
  }

  @Test func halfwayValuesRoundUpAsInJavaScript() {
    // JavaScript's toFixed rounds an exact half up; C's printf to even.
    #expect(Format.fixed(0.25, digits: 1) == "0.3")
    #expect(Format.fixed(0.125, digits: 2) == "0.13")
    #expect(Format.fixed(2.5, digits: 0) == "3")
    // 1.005 is really 1.00499999..., so both say 1.00.
    #expect(Format.fixed(1.005, digits: 2) == "1.00")
    #expect(Format.jsRound(2.5) == 3)
    #expect(Format.jsRound(-2.5) == -2)
    #expect(Format.jsRound(0.49999999999999994) == 0)
  }

  @Test func countsUseThousandsSeparators() {
    #expect(Format.count(1204, locale: Locale(identifier: "en_US")) == "1,204")
  }
}
