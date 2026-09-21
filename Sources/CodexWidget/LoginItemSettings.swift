import Combine
import ServiceManagement

@MainActor final class LoginItemSettings: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var error: String?
    private let readStatus: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void

    init(readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
         register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
         unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() }) {
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
        self.status = readStatus()
    }

    // Pending approval is registered, but isn't yet authorized to run at login.
    var isRequested: Bool { status == .enabled || status == .requiresApproval }

    func reload() { status = readStatus() }

    func setEnabled(_ enabled: Bool) {
        error = nil
        do {
            if enabled { try register() }
            else { try unregister() }
        } catch {
            self.error = "Could not change Open at login. \(error.localizedDescription)"
        }
        reload() // macOS is the source of truth, including after a failed change.
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
