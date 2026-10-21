import AppKit

/// Development-only host: one resizable window running the saver view outside the screen saver host.
/// It reads settings from its own standard defaults (`com.aaronmashburn.asciiquarium.preview`), and
/// remembers the window frame. Launch arguments for testing: `-ignoreOcclusion YES` keeps animating
/// while covered, and `-thumbnail YES` runs the view in its preview (System Settings thumbnail) mode.
@main
@MainActor
final class PreviewApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var timer: Timer?

    static func main() {
        let app = NSApplication.shared
        let delegate = PreviewApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMenu()

        let frame = NSRect(x: 0, y: 0, width: 1200, height: 720)
        let args = UserDefaults.standard
        guard let view = AsciiquariumView(
            frame: frame, isPreview: args.bool(forKey: "thumbnail"), store: SettingsStore(defaults: .standard))
        else { return }
        view.autoresizingMask = [.width, .height]
        view.pausesWhenOccluded = !args.bool(forKey: "ignoreOcclusion")

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Asciiquarium Preview"
        window.contentView = view
        window.center()
        window.setFrameAutosaveName("Preview")
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate()

        timer = Timer.scheduledTimer(withTimeInterval: view.animationTimeInterval, repeats: true) { _ in
            MainActor.assumeIsolated { view.animateOneFrame() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func makeMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Asciiquarium Preview",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let menu = NSMenu()
        menu.addItem(appItem)
        return menu
    }
}
