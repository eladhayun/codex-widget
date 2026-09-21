import XCTest
@testable import CodexWidget

final class AppearanceTests: XCTestCase {
    @MainActor func testAppearanceDefaultsPersistsAndRecoversInvalidPreference() {
        let suite = "AppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsageStore(defaults: defaults)
        XCTAssertEqual(store.appearance, .auto)
        XCTAssertNil(store.appearance.colorScheme)
        store.appearance = .dark
        XCTAssertEqual(UsageStore(defaults: defaults).appearance, .dark)
        store.appearance = .light
        XCTAssertEqual(UsageStore(defaults: defaults).appearance, .light)
        store.appearance = .auto
        XCTAssertEqual(UsageStore(defaults: defaults).appearance, .auto)
        defaults.set("unknown", forKey: "appearance")
        XCTAssertEqual(UsageStore(defaults: defaults).appearance, .auto)
    }
}
