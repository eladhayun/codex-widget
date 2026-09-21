import Foundation

public enum CodexError: LocalizedError {
    case missingExecutable, disconnected, timeout, malformedResponse
    case rpc(Int, String)
    public var errorDescription: String? {
        switch self {
        case .missingExecutable: return "Codex CLI not found. Install Codex or set its path in Settings."
        case .disconnected: return "Codex connection closed. Retrying automatically."
        case .timeout: return "Codex did not respond in time. Retrying automatically."
        case .malformedResponse: return "Codex returned an unreadable response. Try updating Codex."
        case .rpc(let code, _): return "Codex request failed (\(code)). Check your connection and run codex login if needed."
        }
    }
}

/// A single read-only app-server connection. All mutable state is main-actor isolated.
@MainActor public protocol CodexServing: AnyObject {
    var onNotification: ((String, Data) -> Void)? { get set }
    var onDisconnect: (() -> Void)? { get set }
    var connected: Bool { get }
    func connect(path: String?) async throws
    func read<T: Decodable>(_ method: String, as type: T.Type) async throws -> T
    func stop()
}

@MainActor public final class CodexClient: CodexServing {
    public var onNotification: ((String, Data) -> Void)?
    public var onDisconnect: (() -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var nextID = 0
    private var generation = UUID()
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]
    public private(set) var connected = false
    public init() {}

    public static func executablePath(override: String? = nil) -> String? {
        if let override, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return FileManager.default.isExecutableFile(atPath: override) ? override : nil
        }
        let candidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/Applications/Codex.app/Contents/Resources/codex", "/Applications/ChatGPT.app/Contents/Resources/codex"]
        let pathCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
        return (candidates + pathCandidates).first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func connect(path: String? = nil) async throws {
        try await connect(path: path, arguments: ["app-server", "--stdio"])
    }

    public func connect(path: String?, arguments: [String]) async throws {
        if connected { return }
        stop()
        guard let executable = Self.executablePath(override: path) else { throw CodexError.missingExecutable }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = arguments
        child.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let stdin = Pipe(), stdout = Pipe()
        child.standardInput = stdin
        child.standardOutput = stdout
        // Server logs can include account/config details. Do not persist or display them.
        child.standardError = FileHandle.nullDevice
        let session = generation
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            Task { @MainActor in
                guard let self, self.generation == session else { return }
                if bytes.isEmpty { self.failConnection() } else { self.receive(bytes) }
            }
        }
        child.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == session else { return }
                self.failConnection()
            }
        }
        process = child
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        do {
            try child.run()
            _ = try await request("initialize", params: ["clientInfo": ["name": "codex_widget", "title": "Codex Widget", "version": "0.1.0"]])
            try send(["method": "initialized", "params": [:]])
            connected = true
        } catch {
            stop()
            throw error
        }
    }

    public func request(_ method: String, params: [String: Any] = [:], timeout: TimeInterval = 20) async throws -> Data {
        guard process?.isRunning == true else { throw CodexError.disconnected }
        nextID += 1
        let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            timeouts[id] = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)) } catch { return }
                self?.finish(id, result: .failure(CodexError.timeout))
            }
            do { try send(["id": id, "method": method, "params": params]) }
            catch { finish(id, result: .failure(error)) }
        }
    }

    public func read<T: Decodable>(_ method: String, as type: T.Type) async throws -> T {
        let data = try await request(method)
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw CodexError.malformedResponse }
    }

    private func send(_ message: [String: Any]) throws {
        guard let input else { throw CodexError.disconnected }
        var data = try JSONSerialization.data(withJSONObject: message, options: .withoutEscapingSlashes)
        data.append(0x0a)
        try input.write(contentsOf: data)
    }

    private func receive(_ bytes: Data) {
        buffer.append(bytes)
        guard buffer.count < 8 * 1024 * 1024 else { failConnection(); return }
        while let newline = buffer.firstIndex(of: 0x0a) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                failConnection(); return
            }
            if let method = object["method"] as? String {
                if let id = object["id"] {
                    // This monitor never approves tool calls or supplies authentication tokens.
                    try? send(["id": id, "error": ["code": -32601, "message": "Unsupported client request"]])
                } else if let params = object["params"], let data = try? JSONSerialization.data(withJSONObject: params) {
                    onNotification?(method, data)
                }
            } else if let id = object["id"] as? Int {
                if let error = object["error"] as? [String: Any] {
                    finish(id, result: .failure(CodexError.rpc(error["code"] as? Int ?? -1, error["message"] as? String ?? "")))
                } else if let result = object["result"], let data = try? JSONSerialization.data(withJSONObject: result, options: .fragmentsAllowed) {
                    finish(id, result: .success(data))
                } else { finish(id, result: .failure(CodexError.malformedResponse)) }
            }
        }
    }

    private func finish(_ id: Int, result: Result<Data, Error>) {
        timeouts.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    private func failConnection() {
        stop()
        onDisconnect?()
    }

    public func stop() {
        generation = UUID()
        connected = false
        output?.readabilityHandler = nil
        try? input?.close()
        try? output?.close()
        input = nil; output = nil
        let child = process
        process = nil
        child?.terminationHandler = nil
        if child?.isRunning == true { child?.terminate() }
        buffer.removeAll()
        for id in Array(pending.keys) { finish(id, result: .failure(CodexError.disconnected)) }
    }
}
