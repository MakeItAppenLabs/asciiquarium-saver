import AppKit

/// Development-only host: one resizable window running the saver view outside the screen saver host.
/// It reads settings from its own standard defaults (`com.aaronmashburn.asciiquarium.preview`), and
/// remembers the window frame. Launch arguments for testing: `-ignoreOcclusion YES` keeps animating
/// while covered, and `-thumbnail YES` runs the view in its preview (System Settings thumbnail) mode.
/// The Options sheet opens from the "Options…" menu item (command-comma), or at launch with
/// `-showOptions YES`. Test drivers: `-optionsSnapshot <png path>` writes the sheet to a PNG (appearance
/// `-optionsAppearance dark` for dark), and `-optionsDrive ok|cancel|ok-solid|reopen` changes the
/// controls, clicks the button and quits.
@main
@MainActor
final class PreviewApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var view: AsciiquariumView?
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
        self.view = view

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

        if args.bool(forKey: "showOptions") || args.string(forKey: "optionsDrive") != nil {
            // Let the main window appear first so the sheet has a parent to attach to.
            DispatchQueue.main.async { [weak self] in self?.showOptions(nil) }
        }
    }

    @objc func showOptions(_ sender: Any?) {
        guard let window, let view, view.hasConfigureSheet,
              let sheet = view.configureSheet, window.attachedSheet == nil else { return }
        window.beginSheet(sheet)
        let args = UserDefaults.standard
        if let driver = args.string(forKey: "optionsDrive") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.drive(sheet, script: driver)
            }
        } else if let path = args.string(forKey: "optionsSnapshot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Self.snapshot(sheet, to: path, dark: args.string(forKey: "optionsAppearance") == "dark")
            }
        }
    }

    /// Test driver: sets controls as a person would, snapshots if asked, then clicks a button and quits.
    private func drive(_ sheet: NSWindow, script: String) {
        guard let controller = sheet.windowController as? ConfigSheet else { return }
        func chooseBackground(_ index: Int) {
            controller.backgroundPopup.selectItem(at: index)
            controller.backgroundPopup.sendAction(controller.backgroundPopup.action, to: controller.backgroundPopup.target)
        }
        switch script {
        case "ok":  // Classic, large, fewer specials, many fish, red-to-black gradient
            controller.fishSlider.doubleValue = 0.9
            controller.creatureSetControl.selectedSegment = 1
            controller.specialChecks[.ship]?.state = .off
            controller.specialChecks[.whale]?.state = .off
            controller.textSizeControl.selectedSegment = 2
            chooseBackground(1)
            controller.topWell.color = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        case "ok-solid":  // back to Full, small, everything on, few fish, solid dark blue
            controller.fishSlider.doubleValue = 0.1
            controller.creatureSetControl.selectedSegment = 0
            for box in controller.specialChecks.values { box.state = .on }
            controller.textSizeControl.selectedSegment = 0
            chooseBackground(0)
            controller.solidWell.color = NSColor(srgbRed: 0, green: 0.25, blue: 0.5, alpha: 1)
        case "cancel":  // changes everything that matters, then cancels: nothing may be stored
            controller.fishSlider.doubleValue = 0.0
            controller.creatureSetControl.selectedSegment = 1
            for box in controller.specialChecks.values { box.state = .off }
            controller.textSizeControl.selectedSegment = 1
            chooseBackground(1)
            controller.bottomWell.color = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
        default:  // "reopen": change nothing
            break
        }
        if let path = UserDefaults.standard.string(forKey: "optionsSnapshot") {
            Self.snapshot(sheet, to: path, dark: false)
        }
        if script == "cancel" {
            controller.cancelButton.performClick(nil)
        } else {
            controller.okButton.performClick(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
    }

    private static func snapshot(_ sheet: NSWindow, to path: String, dark: Bool) {
        guard let content = sheet.contentView else { return }
        sheet.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        content.layoutSubtreeIfNeeded()
        // Cache the frame view, which draws the window background, cropped to the content area.
        let target = content.superview ?? content
        let area = target.convert(content.bounds, from: content)
        guard let rep = target.bitmapImageRepForCachingDisplay(in: area) else { return }
        target.cacheDisplay(in: area, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func makeMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Asciiquarium Preview",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let options = NSMenuItem(title: "Options…", action: #selector(showOptions(_:)), keyEquivalent: ",")
        options.target = self
        appMenu.insertItem(options, at: 0)
        appMenu.insertItem(.separator(), at: 1)
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let menu = NSMenu()
        menu.addItem(appItem)
        return menu
    }
}
