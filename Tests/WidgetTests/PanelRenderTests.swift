import AppKit
import SwiftUI
import XCTest
import UsageCore
@testable import CodexWidget

final class PanelRenderTests: XCTestCase {
    @MainActor func testPanelRendersInBothAppearances() throws {
        _ = NSApplication.shared
        let store = UsageStore()
        let decoder = JSONDecoder()
        store.account = try decoder.decode(AccountResponse.self, from: Data(#"{"account":{"type":"chatgpt","email":"preview@example.com","planType":"pro"}}"#.utf8)).account
        store.limits = try decoder.decode(RateLimitsResponse.self, from: Data(#"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":28,"windowDurationMins":300,"resetsAt":1790000000},"secondary":{"usedPercent":65,"windowDurationMins":10080,"resetsAt":1790400000}}}"#.utf8))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        store.usage = try decoder.decode(TokenUsageResponse.self, from: Data("{\"summary\":{\"lifetimeTokens\":24500000,\"peakDailyTokens\":821000,\"longestRunningTurnSec\":7290,\"currentStreakDays\":3,\"longestStreakDays\":14},\"dailyUsageBuckets\":[{\"startDate\":\"\(formatter.string(from: Date()))\",\"tokens\":156200}]}".utf8))
        store.updatedAt = Date()
        store.stale = false
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent(".build/previews")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var panelSize: CGSize?
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
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            XCTAssertGreaterThan(bitmap.pixelsHigh, 400)
            XCTAssertEqual(size.width, 440)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let appearance = scheme == .dark ? "dark" : "light"
            try png.write(to: directory.appendingPathComponent("panel-\(tab.rawValue.lowercased())-\(appearance).png"))
          }
        }
    }
}
