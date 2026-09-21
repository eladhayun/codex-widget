import AppKit
import SwiftUI
import XCTest
import UsageCore
@testable import CodexWidget

final class PanelRenderTests: XCTestCase {
    @MainActor func testPanelRendersInBothAppearances() throws {
        _ = NSApplication.shared
        let suiteName = "CodexWidgetRenderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UsageStore(defaults: defaults)
        let decoder = JSONDecoder()
        let now = Date()
        let shortReset = Int(now.addingTimeInterval(3 * 3600).timeIntervalSince1970)
        let weeklyReset = Int(now.addingTimeInterval(3.25 * 86400).timeIntervalSince1970)
        store.account = try decoder.decode(AccountResponse.self, from: Data(#"{"account":{"type":"chatgpt","email":"preview@example.com","planType":"pro"}}"#.utf8)).account
        store.limits = try decoder.decode(RateLimitsResponse.self, from: Data(#"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":28,"windowDurationMins":300,"resetsAt":\#(shortReset)},"secondary":{"usedPercent":65,"windowDurationMins":10080,"resetsAt":\#(weeklyReset)}}}"#.utf8))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        // Fictional history keeps documentation renders useful without reading a login.
        let buckets: [[String: Any]] = (0..<182).map { offset in
            let date = now.addingTimeInterval(-Double(offset) * 86400)
            let tokens = offset == 0 ? 156200 : (offset % 7 == 0 ? 0 : (offset * 7919) % 821000)
            return ["startDate": formatter.string(from: date), "tokens": tokens]
        }
        let usage: [String: Any] = [
            "summary": ["lifetimeTokens": 24500000, "peakDailyTokens": 821000,
                        "longestRunningTurnSec": 7290, "currentStreakDays": 3, "longestStreakDays": 14],
            "dailyUsageBuckets": buckets
        ]
        store.usage = try decoder.decode(TokenUsageResponse.self, from: JSONSerialization.data(withJSONObject: usage))
        store.updatedAt = now
        store.stale = false
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent(".build/previews")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var panelSize: CGSize?
        for mode in AppAppearance.allCases {
            store.appearance = mode
            for highContrast in [false, true] {
                for tab in PanelTab.allCases {
                    for scheme in [ColorScheme.light, .dark] {
                        let host = NSHostingView(rootView: UsagePanel(store: store, initialTab: tab)
                            .background(scheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.13) : .white)
                            .environment(\.colorScheme, scheme))
                        let size = host.fittingSize
                        if let panelSize {
                            XCTAssertEqual(size.height, panelSize.height, accuracy: 0.5, "Switching tabs must not resize the panel")
                        } else { panelSize = size }
                        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
                        window.contentView = host
                        window.appearance = NSAppearance(named: highContrast
                            ? (scheme == .dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua)
                            : (scheme == .dark ? .darkAqua : .aqua))
                        host.layoutSubtreeIfNeeded()
                        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        XCTAssertGreaterThan(bitmap.pixelsHigh, 400)
                        XCTAssertEqual(size.width, 440)
                        let background = try XCTUnwrap(bitmap.colorAt(x: 20, y: 60)?.usingColorSpace(.deviceRGB))
                        let isDark = (mode.colorScheme ?? scheme) == .dark
                        XCTAssertEqual(background.redComponent < 0.5, isDark, "Background must honor \(mode) on \(scheme)")
                        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        let appearance = scheme == .dark ? "dark" : "light"
                        let suffix = mode == .auto && !highContrast ? "" : "-\(mode.rawValue)-\(highContrast ? "contrast" : "glass")"
                        try png.write(to: directory.appendingPathComponent("panel-\(tab.rawValue.lowercased())-\(appearance)\(suffix).png"))
                    }
                }
            }
        }
        store.appearance = .auto
        let settings = NSHostingView(rootView: SettingsView(store: store, loginItem: LoginItemSettings(readStatus: { .notRegistered }, register: {}, unregister: {}))
            .defaultAppStorage(defaults).environment(\.colorScheme, .light).background(Color.white))
        let settingsSize = settings.fittingSize
        let settingsWindow = NSWindow(contentRect: NSRect(origin: .zero, size: settingsSize),
            styleMask: .borderless, backing: .buffered, defer: false)
        settingsWindow.contentView = settings
        settingsWindow.appearance = NSAppearance(named: .aqua)
        settings.layoutSubtreeIfNeeded()
        let settingsBitmap = try XCTUnwrap(settings.bitmapImageRepForCachingDisplay(in: settings.bounds))
        settings.cacheDisplay(in: settings.bounds, to: settingsBitmap)
        XCTAssertEqual(settingsSize.width, 450)
        let settingsPNG = try XCTUnwrap(settingsBitmap.representation(using: .png, properties: [:]))
        try settingsPNG.write(to: directory.appendingPathComponent("settings.png"))
    }
}
