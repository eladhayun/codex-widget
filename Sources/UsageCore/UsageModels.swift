import Foundation

public struct AccountResponse: Decodable {
    public let account: Account?
    public struct Account: Decodable {
        public let type: String
        public let email: String?
        public let planType: String?
        public let accountId: String?
        public var identity: String { [type, accountId ?? "", email ?? "", planType ?? ""].joined(separator: "|") }
    }
}

public struct QuotaWindow: Decodable {
    public let usedPercent: Double
    public let windowDurationMins: Int?
    public let resetsAt: Double?
    public var remaining: Double { max(0, min(100, 100 - usedPercent)) }
    public func timeRemainingFraction(now: Date = Date()) -> Double? {
        guard let resetsAt, let minutes = windowDurationMins, minutes > 0 else { return nil }
        return max(0, min(1, (resetsAt - now.timeIntervalSince1970) / (Double(minutes) * 60)))
    }
    public var durationLabel: String {
        guard let minutes = windowDurationMins else { return "Quota window" }
        if minutes % 10080 == 0 { return "\(minutes / 10080)-week window" }
        if minutes % 1440 == 0 { return "\(minutes / 1440)-day window" }
        if minutes % 60 == 0 { return "\(minutes / 60)-hour window" }
        return "\(minutes)-minute window"
    }
    public func resetLabel(now: Date = Date()) -> String {
        guard let resetsAt else { return "Reset time unavailable" }
        let seconds = Int(resetsAt - now.timeIntervalSince1970)
        guard seconds > 0 else { return "Reset due · awaiting refresh" }
        let minutes = max(1, (seconds + 59) / 60)
        if minutes >= 1440 { return "Resets in \(minutes / 1440)d \((minutes % 1440) / 60)h" }
        if minutes >= 60 { return "Resets in \(minutes / 60)h \(minutes % 60)m" }
        return "Resets in \(minutes)m"
    }
}

public struct QuotaBucket: Decodable {
    public let limitId: String?
    public let limitName: String?
    public let primary: QuotaWindow?
    public let secondary: QuotaWindow?
}

public struct QuotaRow: Identifiable {
    public let id: String
    public let name: String
    public let window: QuotaWindow
}

public struct RateLimitsResponse: Decodable {
    public let rateLimits: QuotaBucket?
    public let rateLimitsByLimitId: [String: QuotaBucket]?
    public var rows: [QuotaRow] {
        let buckets: [(String, QuotaBucket)]
        if let map = rateLimitsByLimitId, !map.isEmpty {
            buckets = map.sorted { $0.key < $1.key }
        } else if let rateLimits {
            buckets = [(rateLimits.limitId ?? "codex", rateLimits)]
        } else { buckets = [] }
        return buckets.flatMap { key, bucket in
            [("primary", bucket.primary), ("secondary", bucket.secondary)].compactMap { slot, window in
                window.map { QuotaRow(id: "\(key).\(slot)", name: bucket.limitName ?? key, window: $0) }
            }
        }
    }
    public var remaining: Double? { rows.map(\.window.remaining).min() }
}

public struct TokenUsageResponse: Decodable {
    public struct Summary: Decodable {
        public let lifetimeTokens: Int64?
        public let peakDailyTokens: Int64?
        public let longestRunningTurnSec: Int64?
        public let currentStreakDays: Int64?
        public let longestStreakDays: Int64?
    }
    public struct DailyBucket: Decodable {
        public let startDate: String
        public let tokens: Int64
    }
    public let summary: Summary
    public let dailyUsageBuckets: [DailyBucket]?
    public var latestReportedDate: String? { dailyUsageBuckets?.map(\.startDate).max() }

    public func todayDisplay(now: Date = Date()) -> String {
        if let tokens = todayTokens(now: now) { return UsageFormatting.tokens(tokens) }
        return dailyUsageBuckets == nil ? "Unavailable" : "Not reported yet"
    }
    // The service supplies date-only buckets without a timezone. Use UTC explicitly
    // in the UI instead of silently presenting them as local-calendar totals.
    public func todayTokens(now: Date = Date()) -> Int64? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: now)
        return dailyUsageBuckets?.first { $0.startDate == date }?.tokens
    }
}

public enum UsageFormatting {
    public static func tokens(_ count: Int64?) -> String {
        guard let count else { return "Unavailable" }
        return count.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }
}
