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
        Settings { SettingsView(store: delegate.store) }
    }
}


@MainActor struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @AppStorage("codexPath") private var path = ""
    @StateObject private var loginItem: LoginItemSettings

    init(store: UsageStore, loginItem: LoginItemSettings? = nil) {
        self.store = store
        _loginItem = StateObject(wrappedValue: loginItem ?? LoginItemSettings())
    }

    var body: some View {
        Form {
            Text("Uses your existing Codex login. Run codex login in Terminal if you need to sign in.")
            Toggle("Open at login", isOn: Binding(
                get: { loginItem.isRequested }, set: { loginItem.setEnabled($0) }))
            Text("Start automatically when you sign in to your Mac, including after a restart.")
                .font(.caption).foregroundStyle(.secondary)
            if loginItem.status == .requiresApproval {
                Text("Allow Codex Widget in System Settings → General → Login Items to finish enabling this.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Login Items") { loginItem.openSystemSettings() }
            }
            if loginItem.status == .notFound {
                Text("Install Codex Widget in Applications and open it there to set up automatic startup.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = loginItem.error {
                Text(error).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("Refresh interval", selection: $store.refreshInterval) {
                ForEach(RefreshInterval.allCases, id: \.self) { interval in
                    Text(interval.label).tag(interval)
                }
            }
            Text("Changes apply immediately. Manual refresh and refresh on wake remain available.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Codex executable", text: $path, prompt: Text("Auto-detect"))
            Text("Leave empty to auto-detect. Restart Codex Widget after changing this path.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 450)
            .onAppear { loginItem.reload() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                loginItem.reload()
            }
    }
}
