import Foundation
import XCTest
@testable import UsageCore

final class LocalUsageReaderTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-09-21T12:00:00Z")!
    func metadata(id: String = "test", fork: Bool = false) -> Data {
        Data("{\"type\":\"session_meta\",\"payload\":{\"id\":\"\(id)\",\"model_provider\":\"openai\",\"timestamp\":\"2026-09-21T10:00:00Z\"\(fork ? ",\"forked_from_id\":\"parent\"" : "")}}".utf8)
    }
    func event(_ time: String, total: Int64, last: Int64 = 10) -> Data {
        Data("{\"timestamp\":\"\(time)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":\(total)},\"last_token_usage\":{\"total_tokens\":\(last)}}}}".utf8)
    }
    func testRollingWindowUsesDeltasAndIgnoresRepeatedCounters() {
        var parser = TokenCounter(cutoff: now.addingTimeInterval(-86400), now: now)
        _ = parser.consume(metadata())
        XCTAssertNil(parser.consume(event("2026-09-20T11:59:00Z", total: 1000)))
        XCTAssertEqual(parser.consume(event("2026-09-20T12:01:00Z", total: 1120))?.tokens, 120)
        XCTAssertNil(parser.consume(event("2026-09-20T12:02:00Z", total: 1120)))
        XCTAssertEqual(parser.consume(event("2026-09-21T11:00:00.000Z", total: 1200))?.tokens, 80)
        XCTAssertNil(parser.consume(event("2026-09-21T13:00:00Z", total: 1300)))
    }
    func testInitialAndResetCountersDoNotCountInheritedTotals() {
        var parser = TokenCounter(cutoff: now.addingTimeInterval(-86400), now: now)
        _ = parser.consume(metadata())
        XCTAssertEqual(parser.consume(event("2026-09-21T10:00:00Z", total: 100000, last: 50))?.tokens, 50)
        XCTAssertEqual(parser.consume(event("2026-09-21T11:00:00Z", total: 100, last: 20))?.tokens, 20)
    }
    func testForkSkipsInheritedHistory() {
        var parser = TokenCounter(cutoff: now.addingTimeInterval(-86400), now: now)
        _ = parser.consume(metadata(fork: true))
        XCTAssertNil(parser.consume(event("2026-09-21T09:00:00Z", total: 100)))
        XCTAssertEqual(parser.consume(event("2026-09-21T11:00:00Z", total: 150))?.tokens, 50)
    }
    func testScannerDeduplicatesArchivedCopiesAndWaitsForCompleteLines() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        var data = metadata()
        data.append(10)
        data.append(event("2026-09-21T10:00:00Z", total: 30, last: 30))
        data.append(10)
        data.append(event("2026-09-21T11:00:00Z", total: 80, last: 50))
        data.append(10)
        data.append(Data("{\"type\":\"event_msg\"".utf8))
        for name in ["sessions", "archived_sessions"] {
            let directory = home.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent("test.jsonl"))
        }
        let snapshot = LocalUsageReader.scan(home: home, now: now)
        XCTAssertEqual(snapshot?.tokens, 80)
        XCTAssertEqual(snapshot?.partial, false)
    }
    func testMissingDirectoryDoesNotReportZero() {
        XCTAssertNil(LocalUsageReader.scan(home: URL(fileURLWithPath: "/private/tmp/no-codex-\(UUID().uuidString)"), now: now))
    }
}
