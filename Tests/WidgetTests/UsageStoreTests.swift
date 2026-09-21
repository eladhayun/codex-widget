import XCTest
import AppKit
import UsageCore
@testable import CodexWidget

@MainActor private final class FakeClient: CodexServing {
    var onNotification: ((String, Data) -> Void)?
    var onDisconnect: (() -> Void)?
    var connected = false
    var email = "first@example.com"
    var signedOut = false
    var failLimits = false
    var failTokens = false
    var accountReads = 0
    var todayTokens: Int64?
    var beforeLimits: (() async -> Void)?
    func connect(path: String?) async throws { connected = true }
    func stop() { connected = false }
    func read<T: Decodable>(_ method: String, as type: T.Type) async throws -> T {
        let json: String
        switch method {
        case "account/read":
            accountReads += 1
            json = signedOut ? #"{"account":null}"# : "{\"account\":{\"type\":\"chatgpt\",\"email\":\"\(email)\",\"planType\":\"plus\"}}"
        case "account/rateLimits/read":
            await beforeLimits?()
            if failLimits { throw CodexError.disconnected }
            json = #"{"rateLimits":{"primary":{"usedPercent":20}}}"#
        default:
            if failTokens { throw CodexError.rpc(-32601, "Unsupported") }
            if let todayTokens {
                let date = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
                json = "{\"summary\":{\"lifetimeTokens\":12345},\"dailyUsageBuckets\":[{\"startDate\":\"\(date)\",\"tokens\":\(todayTokens)}]}"
            } else { json = #"{"summary":{"lifetimeTokens":12345}}"# }
        }
        return try JSONDecoder().decode(type, from: Data(json.utf8))
    }
}

final class UsageStoreTests: XCTestCase {
    @MainActor private func testDefaults() -> UserDefaults {
        let name = "CodexWidgetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    @MainActor private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for the refresh scheduler")
    }

    @MainActor func testRefreshIntervalPersistsAndControlsStaleness() async {
        let defaults = testDefaults()
        defaults.set(-1, forKey: "refreshIntervalSeconds")
        let client = FakeClient()
        let store = UsageStore(client: client, defaults: defaults, readLocalUsage: { nil })
        XCTAssertEqual(store.refreshInterval, .oneMinute)
        store.refreshInterval = .fiveMinutes
        let restored = UsageStore(client: FakeClient(), defaults: defaults, readLocalUsage: { nil })
        XCTAssertEqual(restored.refreshInterval, .fiveMinutes)
        await store.refresh()
        store.updatedAt = Date().addingTimeInterval(-90)
        await store.refreshIfNeeded()
        XCTAssertEqual(client.accountReads, 1)
        store.refreshInterval = .thirtySeconds
        await store.refreshIfNeeded()
        XCTAssertEqual(client.accountReads, 2)
    }

    @MainActor func testIntervalChangeReschedulesPollingAndPreservesBackoff() async throws {
        let client = FakeClient()
        var delays: [TimeInterval] = []
        let store = UsageStore(client: client, defaults: testDefaults(), sleep: { delay in
            delays.append(delay)
            try await Task.sleep(nanoseconds: 3_600_000_000_000)
        }, readLocalUsage: { nil })
        store.start()
        defer { store.stop() }
        try await waitUntil { delays == [60] }
        store.refreshInterval = .fifteenMinutes
        try await waitUntil { delays.last == 900 }
        XCTAssertEqual(client.accountReads, 1, "Changing settings should reschedule, not start overlapping reads")
        client.failLimits = true
        await store.refresh()
        try await waitUntil { delays.last == 5 }
        store.refreshInterval = .fifteenSeconds
        await store.refresh()
        try await waitUntil { delays.last == 10 }
        client.failLimits = false
        await store.refresh()
        try await waitUntil { delays.last == 15 }
        store.stop()
        let sleepsAfterStop = delays.count
        store.refreshInterval = .twoMinutes
        await Task.yield()
        XCTAssertEqual(delays.count, sleepsAfterStop)
        XCTAssertFalse(client.connected)
    }

    @MainActor func testPollingContinuesAfterTimerFires() async throws {
        let client = FakeClient()
        var sleeps = 0
        let store = UsageStore(client: client, defaults: testDefaults(), sleep: { _ in
            sleeps += 1
            if sleeps == 1 { await Task.yield() }
            else { try await Task.sleep(nanoseconds: 3_600_000_000_000) }
        }, readLocalUsage: { nil })
        store.start()
        defer { store.stop() }
        try await waitUntil { sleeps == 2 }
        XCTAssertEqual(client.accountReads, 2)
        XCTAssertFalse(store.stale)
    }

    @MainActor func testIntervalChangeDuringReadWaitsForCompletion() async throws {
        let client = FakeClient()
        var delays: [TimeInterval] = []
        let store = UsageStore(client: client, defaults: testDefaults(), sleep: { delay in
            delays.append(delay)
            try await Task.sleep(nanoseconds: 3_600_000_000_000)
        }, readLocalUsage: { nil })
        store.start()
        defer { store.stop() }
        try await waitUntil { delays.count == 1 }
        var gate: CheckedContinuation<Void, Never>?
        client.beforeLimits = { await withCheckedContinuation { gate = $0 } }
        let refresh = Task { await store.refresh() }
        try await waitUntil { gate != nil }
        store.refreshInterval = .twoMinutes
        await store.refresh() // Must be ignored while the first read is suspended.
        XCTAssertEqual(client.accountReads, 2)
        XCTAssertEqual(delays.count, 1)
        gate?.resume()
        await refresh.value
        try await waitUntil { delays.last == 120 }
        XCTAssertFalse(store.stale)
    }

    @MainActor func testLocalFallbackOnlyWhenTodaysAccountReportIsMissing() async {
        let client = FakeClient()
        var localReads = 0
        let store = UsageStore(client: client, readLocalUsage: {
            localReads += 1
            return LocalUsageSnapshot(tokens: 4321, partial: false)
        })
        await store.refresh()
        XCTAssertTrue(store.usesLocalFallback)
        XCTAssertEqual(store.localUsage?.tokens, 4321)
        client.todayTokens = 0
        await store.refresh()
        XCTAssertFalse(store.usesLocalFallback)
        XCTAssertNil(store.localUsage)
        XCTAssertEqual(localReads, 1)
        XCTAssertEqual(store.usage?.todayTokens(), 0)
    }

    @MainActor func testWakeRefreshesAndStopDisconnects() async throws {
        let client = FakeClient()
        let store = UsageStore(client: client, readLocalUsage: { nil })
        store.start()
        defer { store.stop() }
        for _ in 0..<100 where client.accountReads == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(client.accountReads, 1)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        for _ in 0..<100 where client.accountReads < 2 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(client.accountReads, 2)
        store.stop()
        XCTAssertFalse(client.connected)
    }

    @MainActor func testUnsupportedTokensPreserveQuotas() async {
        let client = FakeClient()
        client.failTokens = true
        let store = UsageStore(client: client, readLocalUsage: { nil })
        await store.refresh()
        XCTAssertEqual(store.limits?.remaining, 80)
        XCTAssertNil(store.usage)
        XCTAssertNotNil(store.tokenMessage)
        XCTAssertFalse(store.stale)
    }

    @MainActor func testFailureRetainsSnapshotThenRecovers() async {
        let client = FakeClient()
        let store = UsageStore(client: client, readLocalUsage: { nil })
        await store.refresh()
        let updated = store.updatedAt
        client.failLimits = true
        await store.refresh()
        XCTAssertEqual(store.limits?.remaining, 80)
        XCTAssertEqual(store.updatedAt, updated)
        XCTAssertTrue(store.stale)
        XCTAssertNotNil(store.error)
        client.failLimits = false
        await store.refresh()
        XCTAssertFalse(store.stale)
        XCTAssertNil(store.error)
    }

    @MainActor func testNewAccountDoesNotKeepPreviousAccountDataOnFailure() async {
        let client = FakeClient()
        let store = UsageStore(client: client, readLocalUsage: { nil })
        await store.refresh()
        client.email = "second@example.com"
        client.failLimits = true
        await store.refresh()
        XCTAssertNil(store.limits)
        XCTAssertNil(store.usage)
        XCTAssertNil(store.updatedAt)
        XCTAssertTrue(store.stale)
    }

    @MainActor func testSignOutClearsUsage() async {
        let client = FakeClient()
        let store = UsageStore(client: client, readLocalUsage: { nil })
        await store.refresh()
        client.signedOut = true
        await store.refresh()
        XCTAssertNil(store.limits)
        XCTAssertNil(store.account)
        XCTAssertNotNil(store.error)
    }
}
