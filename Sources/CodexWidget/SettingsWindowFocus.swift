import AppKit
import SwiftUI

/// Tracks only the Settings window so a menu-bar action cannot focus the panel.
@MainActor enum SettingsWindowFocus {
    private static weak var window: NSWindow?
    private static var awaitingWindow = false

    static func open(using openSettings: () -> Void) {
        awaitingWindow = true
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        focusIfReady()
    }

    static func attach(_ window: NSWindow) {
        self.window = window
        focusIfReady()
    }

    private static func focusIfReady() {
        guard awaitingWindow, let window else { return }
        awaitingWindow = false
        // Let SwiftUI finish presenting the scene and dismissing the menu panel.
        DispatchQueue.main.async { [weak window] in
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }
    }
}

struct SettingsWindowReader: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowView { WindowView() }
    func updateNSView(_ nsView: WindowView, context: Context) {}

    final class WindowView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { SettingsWindowFocus.attach(window) }
        }
    }
}
