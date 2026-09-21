import AppKit
import SwiftUI
#if canImport(UsageCore)
import UsageCore
#endif

@MainActor final class UsageStore: ObservableObject {
    @Published var account: AccountResponse.Account?
    @Published var limits: RateLimitsResponse?
    @Published var usage: TokenUsageResponse?
    @Published var localUsage: LocalUsageSnapshot?
    var usesLocalFallback: Bool { usage?.todayTokens() == nil && localUsage != nil }
    @Published var updatedAt: Date?
    @Published var error: String?
    @Published var tokenMessage: String?
    @Published var refreshing = false
    @Published var stale = true
    let client: any CodexServing
    private var loop: Task<Void, Never>?
    private var failures = 0
    private var accountRevision = 0
    private var observers: [NSObjectProtocol] = []
    private let readLocalUsage: () async -> LocalUsageSnapshot?

    init(client: (any CodexServing)? = nil, readLocalUsage: @escaping () async -> LocalUsageSnapshot? = { await LocalUsageReader.read() }) {
        self.client = client ?? CodexClient()
        self.readLocalUsage = readLocalUsage
    }

    func start() {
        client.onDisconnect = { [weak self] in
            self?.stale = true
            self?.error = CodexError.disconnected.localizedDescription
        }
        client.onNotification = { [weak self] method, data in
            guard let self else { return }
            if method == "account/updated" {
                self.accountRevision += 1
                self.account = nil; self.limits = nil; self.usage = nil; self.localUsage = nil; self.updatedAt = nil
                self.stale = true
                Task { await self.refresh() }
            } else if method == "account/rateLimits/updated", self.account != nil, !self.refreshing {
                // Re-read the complete set; notifications can contain just one bucket.
                Task { await self.refresh() }
            }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        })
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let delay = self.map { $0.failures == 0 ? 60.0 : min(300, 5 * pow(2, Double(min($0.failures - 1, 6)))) } ?? 60
                do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
            }
        }
    }

    func refreshIfNeeded() async {
        if stale || updatedAt.map({ Date().timeIntervalSince($0) >= 60 }) ?? true { await refresh() }
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let revision = accountRevision
        do {
            try await client.connect(path: UserDefaults.standard.string(forKey: "codexPath"))
            let response = try await client.read("account/read", as: AccountResponse.self)
            guard revision == accountRevision else { return }
            if account?.identity != response.account?.identity {
                limits = nil; usage = nil; localUsage = nil; updatedAt = nil; stale = true
            }
            account = response.account
            guard let account else {
                error = "Sign in using codex login in Terminal, then refresh."
                failures += 1; return
            }
            guard account.type != "apiKey" else {
                error = "This login uses an API key. Run codex login with your ChatGPT account to see plan quotas."
                failures += 1; return
            }
            let newLimits = try await client.read("account/rateLimits/read", as: RateLimitsResponse.self)
            var newUsage: TokenUsageResponse?
            var usageError: String?
            do { newUsage = try await client.read("account/usage/read", as: TokenUsageResponse.self) }
            catch { usageError = "Token activity is unavailable for this account or Codex version." }
            let recentLocalUsage = newUsage?.todayTokens() == nil ? await readLocalUsage() : nil
            guard revision == accountRevision else { return }
            limits = newLimits; usage = newUsage; localUsage = recentLocalUsage; tokenMessage = usageError
            updatedAt = Date()
            stale = !client.connected
            error = stale ? CodexError.disconnected.localizedDescription : nil
            failures = stale ? failures + 1 : 0
        } catch {
            stale = true
            self.error = error.localizedDescription
            failures += 1
            client.stop()
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        client.stop()
    }
}
