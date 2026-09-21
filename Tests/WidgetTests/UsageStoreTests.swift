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
    func connect(path: String?) async throws { connected = true }
    func stop() { connected = false }
    func read<T: Decodable>(_ method: String, as type: T.Type) async throws -> T {
        let json: String
        switch method {
        case "account/read":
            accountReads += 1
            json = signedOut ? #"{"account":null}"# : "{\"account\":{\"type\":\"chatgpt\",\"email\":\"\(email)\",\"planType\":\"plus\"}}"
        case "account/rateLimits/read":
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
