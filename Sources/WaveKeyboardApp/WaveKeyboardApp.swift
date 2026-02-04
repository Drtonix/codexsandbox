import AppKit
import SwiftUI

@main
final class WaveKeyboardApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    static func main() {
        let app = NSApplication.shared
        let delegate = WaveKeyboardApp()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let contentView = WaveScreen()
            .frame(minWidth: 900, minHeight: 520)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.title = "Wave Keyboard"
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
