import Foundation
import XCTest
@testable import UsageCore

final class UsageModelsTests: XCTestCase {
    private func decode<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testMultipleBucketsTakePrecedenceAndMostDepletedWins() throws {
        let response = try decode(#"{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":25,"windowDurationMins":300},"secondary":{"usedPercent":65,"windowDurationMins":10080}},"extra":{"primary":{"usedPercent":10}}}}"#, as: RateLimitsResponse.self)
        XCTAssertEqual(response.rows.count, 3)
        XCTAssertEqual(response.remaining, 35)
        XCTAssertEqual(response.rows.first?.window.durationLabel, "5-hour window")
        XCTAssertEqual(response.rows[1].window.durationLabel, "1-week window")
    }

    func testLegacyBucketAndClamping() throws {
        let response = try decode(#"{"rateLimits":{"primary":{"usedPercent":120},"secondary":{"usedPercent":-10}},"rateLimitsByLimitId":{}}"#, as: RateLimitsResponse.self)
        XCTAssertEqual(response.rows.map(\.window.remaining), [0, 100])
        XCTAssertEqual(response.remaining, 0)
    }

    func testMissingLimitsAreNotZero() throws {
        XCTAssertNil(try decode(#"{"rateLimits":null}"#, as: RateLimitsResponse.self).remaining)
    }

    func testMissingTokensAreNotZeroAndDateIsUTC() throws {
        let usage = try decode(#"{"summary":{"lifetimeTokens":null},"dailyUsageBuckets":[{"startDate":"2026-09-21","tokens":12345}]}"#, as: TokenUsageResponse.self)
        XCTAssertNil(usage.summary.lifetimeTokens)
        let now = ISO8601DateFormatter().date(from: "2026-09-21T23:30:00Z")!
        XCTAssertEqual(usage.todayTokens(now: now), 12345)
        XCTAssertNil(usage.todayTokens(now: now.addingTimeInterval(86400)))
        XCTAssertEqual(UsageFormatting.tokens(nil), "Unavailable")
        XCTAssertEqual(UsageFormatting.tokens(0), "0")
    }

    func testNullBucketsAndLargeTokenTotals() throws {
        let usage = try decode(#"{"summary":{"lifetimeTokens":9876543210},"dailyUsageBuckets":null}"#, as: TokenUsageResponse.self)
        XCTAssertEqual(usage.summary.lifetimeTokens, 9_876_543_210)
        XCTAssertNil(usage.todayTokens())
    }

    func testStatsDecodeAndRemainOptionalOnOlderResponses() throws {
        let usage = try decode(#"{"summary":{"peakDailyTokens":821000,"longestRunningTurnSec":7290,"currentStreakDays":3,"longestStreakDays":14}}"#, as: TokenUsageResponse.self)
        XCTAssertEqual(usage.summary.peakDailyTokens, 821000)
        XCTAssertEqual(usage.summary.longestRunningTurnSec, 7290)
        XCTAssertEqual(usage.summary.currentStreakDays, 3)
        XCTAssertEqual(usage.summary.longestStreakDays, 14)
        let legacy = try decode(#"{"summary":{"lifetimeTokens":123}}"#, as: TokenUsageResponse.self)
        XCTAssertNil(legacy.summary.currentStreakDays)
        XCTAssertNil(legacy.summary.peakDailyTokens)
    }

    func testResetDoesNotPretendQuotaReplenished() throws {
        let window = try decode(#"{"usedPercent":100,"resetsAt":1000}"#, as: QuotaWindow.self)
        XCTAssertEqual(window.resetLabel(now: Date(timeIntervalSince1970: 1100)), "Reset due · awaiting refresh")
        XCTAssertEqual(window.remaining, 0)
        XCTAssertEqual(window.resetLabel(now: Date(timeIntervalSince1970: 900)), "Resets in 2m")
    }

    func testWeeklyTimeRemainingUsesWindowLengthAndClamps() throws {
        let window = try decode(#"{"usedPercent":95,"windowDurationMins":10080,"resetsAt":604800}"#, as: QuotaWindow.self)
        XCTAssertEqual(window.timeRemainingFraction(now: Date(timeIntervalSince1970: 302400)), 0.5)
        XCTAssertEqual(window.timeRemainingFraction(now: Date(timeIntervalSince1970: 604800)), 0)
        XCTAssertEqual(window.timeRemainingFraction(now: Date(timeIntervalSince1970: 700000)), 0)
        XCTAssertEqual(window.timeRemainingFraction(now: Date(timeIntervalSince1970: -100)), 1)
        let unknown = try decode(#"{"usedPercent":10,"windowDurationMins":0}"#, as: QuotaWindow.self)
        XCTAssertNil(unknown.timeRemainingFraction())
    }

    func testMissingCurrentDailyBucketIsNotReportedRatherThanZero() throws {
        let now = ISO8601DateFormatter().date(from: "2026-09-21T12:00:00Z")!
        let delayed = try decode(#"{"summary":{},"dailyUsageBuckets":[{"startDate":"2026-09-20","tokens":300},{"startDate":"2026-09-19","tokens":100}]}"#, as: TokenUsageResponse.self)
        XCTAssertEqual(delayed.todayDisplay(now: now), "Not reported yet")
        XCTAssertEqual(delayed.latestReportedDate, "2026-09-20")
        XCTAssertNil(delayed.todayTokens(now: now))
        let unavailable = try decode(#"{"summary":{},"dailyUsageBuckets":null}"#, as: TokenUsageResponse.self)
        XCTAssertEqual(unavailable.todayDisplay(now: now), "Unavailable")
        let zero = try decode(#"{"summary":{},"dailyUsageBuckets":[{"startDate":"2026-09-21","tokens":0}]}"#, as: TokenUsageResponse.self)
        XCTAssertEqual(zero.todayDisplay(now: now), "0")
    }

    func testMalformedQuotaFailsDecoding() {
        XCTAssertThrowsError(try decode(#"{"rateLimits":{"primary":{"usedPercent":"oops"}}}"#, as: RateLimitsResponse.self))
    }

    func testAccountIdentityChangesWithAccountOrPlan() throws {
        let a = try decode(#"{"account":{"type":"chatgpt","email":"one@example.com","planType":"plus"}}"#, as: AccountResponse.self)
        let b = try decode(#"{"account":{"type":"chatgpt","email":"two@example.com","planType":"plus"}}"#, as: AccountResponse.self)
        XCTAssertNotEqual(a.account?.identity, b.account?.identity)
    }
}
