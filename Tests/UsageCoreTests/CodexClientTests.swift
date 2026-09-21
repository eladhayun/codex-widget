import Foundation
import XCTest
@testable import UsageCore

final class CodexClientTests: XCTestCase {
    // A shell fixture speaks only the monitor protocol; no credentials or network.
    private let server = #"""
    while IFS= read -r line; do
      case "$line" in
        *'"method":"initialize"'*) printf '%s\n' '{"id":1,"result":{}}' ;;
        *'"method":"test/read"'*) printf '%s\n' '{"id":2,"result":{"value":42}}' ;;
        *'"method":"test/unsupported"'*) printf '%s\n' '{"id":2,"error":{"code":-32601,"message":"Method not found"}}' ;;
        *'"method":"test/malformed"'*) printf '%s\n' 'not-json' ;;
        *'"method":"test/exit"'*) exit 0 ;;
      esac
    done
    """#

    @MainActor func testHandshakeAndResponse() async throws {
        let client = CodexClient()
        defer { client.stop() }
        try await client.connect(path: "/bin/sh", arguments: ["-c", server])
        XCTAssertTrue(client.connected)
        let data = try await client.request("test/read")
        XCTAssertEqual((try JSONSerialization.jsonObject(with: data) as? [String: Int])?["value"], 42)
        client.stop()
        XCTAssertFalse(client.connected)
    }

    @MainActor func testUnsupportedMethodPreservesConnection() async throws {
        let client = CodexClient()
        defer { client.stop() }
        try await client.connect(path: "/bin/sh", arguments: ["-c", server])
        do { _ = try await client.request("test/unsupported"); XCTFail("Expected RPC error") }
        catch CodexError.rpc(let code, _) { XCTAssertEqual(code, -32601) }
        XCTAssertTrue(client.connected)
    }

    @MainActor func testTimeoutCompletesPendingRequest() async throws {
        let client = CodexClient()
        defer { client.stop() }
        try await client.connect(path: "/bin/sh", arguments: ["-c", server])
        do { _ = try await client.request("test/hang", timeout: 0.05); XCTFail("Expected timeout") }
        catch CodexError.timeout { }
    }

    @MainActor func testDisconnectAndMalformedResponseFailPendingRequests() async throws {
        for method in ["test/exit", "test/malformed"] {
            let client = CodexClient()
            try await client.connect(path: "/bin/sh", arguments: ["-c", server])
            do { _ = try await client.request(method); XCTFail("Expected disconnect") }
            catch CodexError.disconnected { }
            XCTAssertFalse(client.connected)
            client.stop()
        }
    }
}
