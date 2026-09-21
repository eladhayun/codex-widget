import AppKit
import SwiftUI
#if canImport(UsageCore)
import UsageCore
#endif

@main struct EntryPoint {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--check") {
            Task { await check(); exit(0) }
            RunLoop.main.run()
        } else { CodexWidgetApp.main() }
    }

    @MainActor private static func check() async {
            let client = CodexClient()
            do {
                try await client.connect()
                let account = try await client.read("account/read", as: AccountResponse.self)
                print("Account: \(account.account == nil ? "signed out" : "signed in")")
                let limits = try await client.read("account/rateLimits/read", as: RateLimitsResponse.self)
                print("Quota windows: \(limits.rows.count)")
                do {
                    let usage = try await client.read("account/usage/read", as: TokenUsageResponse.self)
                    print("Lifetime tokens available: \(usage.summary.lifetimeTokens != nil)")
                    print("Daily buckets available: \(usage.dailyUsageBuckets != nil)")
                    print("Daily bucket count: \(usage.dailyUsageBuckets?.count ?? 0)")
                    print("Recent bucket dates: \(usage.dailyUsageBuckets?.map(\.startDate).sorted().suffix(3).joined(separator: ", ") ?? "none")")
                    print("Today's tokens available: \(usage.todayTokens() != nil)")
                    if usage.todayTokens() == nil {
                        let local = await LocalUsageReader.read()
                        print("Local last-24h tokens: \(local.map { String($0.tokens) } ?? "unavailable")")
                        print("Local total partial: \(local?.partial ?? false)")
                    }
                } catch { print("Token usage unavailable: \(error.localizedDescription)") }
                client.stop()
                guard !limits.rows.isEmpty else { exit(2) }
            } catch {
                client.stop()
                print("Check failed: \(error.localizedDescription)")
                exit(1)
            }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store.start()
    }
    func applicationWillTerminate(_ notification: Notification) { store.stop() }
}

struct CodexWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra { UsagePanel(store: delegate.store) } label: {
            Image(systemName: "terminal")
                .symbolRenderingMode(.monochrome)
                .accessibilityLabel("Codex status")
        }
            .menuBarExtraStyle(.window)
        Settings { SettingsView() }
    }
}


struct SettingsView: View {
    @AppStorage("codexPath") private var path = ""
    var body: some View {
        Form {
            Text("Uses your existing Codex login. Run codex login in Terminal if you need to sign in.")
            TextField("Codex executable", text: $path, prompt: Text("Auto-detect"))
            Text("Leave empty to auto-detect. Restart Codex Widget after changing this path. Usage refreshes every 60 seconds while running.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 450)
    }
}
