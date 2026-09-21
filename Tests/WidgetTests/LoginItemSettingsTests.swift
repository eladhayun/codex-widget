import XCTest
import ServiceManagement
@testable import CodexWidget

final class LoginItemSettingsTests: XCTestCase {
    @MainActor func testEnablingAndDisablingUseSystemState() {
        var status = SMAppService.Status.notRegistered
        var registrations = 0
        var removals = 0
        let settings = LoginItemSettings(readStatus: { status }, register: {
            registrations += 1; status = .enabled
        }, unregister: {
            removals += 1; status = .notRegistered
        })
        XCTAssertFalse(settings.isRequested)
        XCTAssertEqual(registrations, 0, "Opening Settings must not register a login item")
        settings.setEnabled(true)
        XCTAssertTrue(settings.isRequested)
        XCTAssertEqual(registrations, 1)
        settings.setEnabled(false)
        XCTAssertFalse(settings.isRequested)
        XCTAssertEqual(removals, 1)
    }

    @MainActor func testApprovalAndExternalChangesAreReflected() {
        var status = SMAppService.Status.notRegistered
        let settings = LoginItemSettings(readStatus: { status }, register: {
            status = .requiresApproval
        }, unregister: { status = .notRegistered })
        settings.setEnabled(true)
        XCTAssertEqual(settings.status, .requiresApproval)
        XCTAssertTrue(settings.isRequested)
        status = .enabled
        settings.reload()
        XCTAssertEqual(settings.status, .enabled)
        status = .notRegistered
        settings.reload()
        XCTAssertFalse(settings.isRequested)
    }

    @MainActor func testErrorsDoNotReportAnUnsuccessfulChangeAsApplied() {
        struct Failure: Error {}
        var status = SMAppService.Status.notRegistered
        let settings = LoginItemSettings(readStatus: { status }, register: { throw Failure() }, unregister: { throw Failure() })
        settings.setEnabled(true)
        XCTAssertFalse(settings.isRequested)
        XCTAssertNotNil(settings.error)
        status = .enabled
        settings.reload()
        settings.setEnabled(false)
        XCTAssertTrue(settings.isRequested)
        XCTAssertNotNil(settings.error)
    }
}
