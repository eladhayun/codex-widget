import Foundation

public struct LocalUsageSnapshot: Sendable {
    public let tokens: Int64
    public let partial: Bool
    public init(tokens: Int64, partial: Bool) { self.tokens = tokens; self.partial = partial }
}

/// Reads only timestamped token counters from local rollouts; conversation text is
/// neither retained nor logged. Work runs off the main actor and reads in chunks.
public enum LocalUsageReader {
    public static func read(now: Date = Date()) async -> LocalUsageSnapshot? {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        return await Task.detached(priority: .utility) { scan(home: home, now: now) }.value
    }

    static func scan(home: URL, now: Date) -> LocalUsageSnapshot? {
        let cutoff = now.addingTimeInterval(-86400)
        var total: Int64 = 0
        var partial = false
        var foundDirectory = false
        var counted = Set<String>()
        for name in ["sessions", "archived_sessions"] {
            let directory = home.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            foundDirectory = true
            guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey], options: [.skipsHiddenFiles], errorHandler: { _, _ in partial = true; return true }) else {
                partial = true; continue
            }
            for case let url as URL in files {
                guard url.pathExtension == "jsonl" else { continue }
                do {
                    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
                    guard values.isRegularFile == true, (values.contentModificationDate ?? .distantFuture) >= cutoff else { continue }
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    var parser = TokenCounter(cutoff: cutoff, now: now)
                    var buffer = Data()
                    var oversizedLine = false
                    while let chunk = try handle.read(upToCount: 65536), !chunk.isEmpty {
                        buffer.append(chunk)
                        while let newline = buffer.firstIndex(of: 10) {
                            let line = Data(buffer.prefix(upTo: newline))
                            buffer.removeSubrange(...newline)
                            if !oversizedLine, let event = parser.consume(line), counted.insert(event.key).inserted {
                                total += event.tokens
                            }
                            oversizedLine = false
                        }
                        if buffer.count > 16 * 1024 * 1024 {
                            buffer.removeAll(); oversizedLine = true; partial = true
                        }
                    }
                    // A trailing line may still be being written. Count it only once
                    // it is terminated on the next refresh.
                    partial = partial || parser.partial
                } catch { partial = true }
            }
        }
        guard foundDirectory, !partial || total > 0 else { return nil }
        return LocalUsageSnapshot(tokens: total, partial: partial)
    }
}

struct TokenCounter {
    struct Event { let key: String; let tokens: Int64 }
    let cutoff: Date
    let now: Date
    private var previous: Int64?
    private var sessionID: String?
    private var forkDate: Date?
    private var supportedProvider = true
    private(set) var partial = false
    private let formatter = ISO8601DateFormatter()

    init(cutoff: Date, now: Date) { self.cutoff = cutoff; self.now = now }

    private func date(_ text: String) -> Date? {
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    mutating func consume(_ line: Data) -> Event? {
        guard line.range(of: Data("\"token_count\"".utf8)) != nil || line.range(of: Data("\"session_meta\"".utf8)) != nil else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = object["payload"] as? [String: Any] else { partial = true; return nil }
        if object["type"] as? String == "session_meta" {
            sessionID = payload["id"] as? String
            supportedProvider = (payload["model_provider"] as? String).map { $0 == "openai" } ?? true
            if payload["forked_from_id"] as? String != nil {
                forkDate = (payload["timestamp"] as? String).flatMap(date)
                if forkDate == nil { partial = true; supportedProvider = false }
            }
            return nil
        }
        guard supportedProvider, object["type"] as? String == "event_msg", payload["type"] as? String == "token_count" else { return nil }
        guard let info = payload["info"] as? [String: Any] else { return nil }
        guard let usage = info["total_token_usage"] as? [String: Any], let total = usage["total_tokens"] as? Int64,
              let timestamp = object["timestamp"] as? String, let time = date(timestamp), let sessionID else { partial = true; return nil }
        let last = (info["last_token_usage"] as? [String: Any])?["total_tokens"] as? Int64
        let delta: Int64
        if let previous, total >= previous { delta = total - previous }
        else {
            // Initial or reset counters may include inherited history. Only count
            // the explicitly reported latest increment, never the whole baseline.
            delta = max(0, min(total, last ?? 0))
            if last == nil, time > cutoff { partial = true }
        }
        previous = total
        guard time > cutoff, time <= now, time >= (forkDate ?? .distantPast), delta > 0 else { return nil }
        return Event(key: "\(sessionID)|\(timestamp)|\(total)", tokens: delta)
    }
}
