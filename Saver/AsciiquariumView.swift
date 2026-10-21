import AppKit
import ScreenSaver
import os
import AquariumKit

private let log = Logger(subsystem: "com.aaronmashburn.asciiquarium", category: "view")

/// The screen saver: one independent aquarium per view, drawn as terminal text.
///
/// The `@objc` name is unique because the host loads every installed saver into one process.
@objc(AMAsciiquariumView)
final class AsciiquariumView: ScreenSaverView {
    static let moduleName = "com.aaronmashburn.asciiquarium"

    let store: SettingsStore
    private var settings: AquariumSettings
    private let backgroundRenderer = BackgroundRenderer()

    /// Everything that depends on the view size and settings, rebuilt together.
    private struct Tank {
        var size: CGSize
        var settings: AquariumSettings
        var renderer: GridRenderer
        var layout: GridLayout
        var aquarium: Aquarium
    }

    private var tank: Tank?
    /// Set by `stopAnimation()` or the host's will-stop notification; cleared by `startAnimation()`.
    private var isStopped = false
    /// Skip frames while the window is fully covered. The Preview app can turn this off for testing
    /// while the screen is locked.
    var pausesWhenOccluded = true

    /// The saver entry point the host calls; settings come from the saver's `ScreenSaverDefaults`.
    override convenience init?(frame: NSRect, isPreview: Bool) {
        let defaults = ScreenSaverDefaults(forModuleWithName: Self.moduleName) ?? .standard
        self.init(frame: frame, isPreview: isPreview, store: SettingsStore(defaults: defaults))
    }

    init?(frame: NSRect, isPreview: Bool, store: SettingsStore) {
        self.store = store
        settings = store.load()
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 0.1
        if !isPreview {
            DistributedNotificationCenter.default().addObserver(
                self,
                selector: #selector(hostWillStop(_:)),
                name: Notification.Name("com.apple.screensaver.willstop"),
                object: nil
            )
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: Lifecycle

    override func startAnimation() {
        super.startAnimation()
        log.debug("startAnimation preview=\(self.isPreview)")
        isStopped = false
        let latest = store.load()
        if latest != settings {
            settings = latest
            tank = nil
        }
    }

    override func stopAnimation() {
        super.stopAnimation()
        log.debug("stopAnimation preview=\(self.isPreview)")
        isStopped = true
        tank = nil
    }

    @objc private func hostWillStop(_ note: Notification) {
        log.debug("com.apple.screensaver.willstop")
        stopAnimation()
    }

    /// False when there's nothing to animate for: stopped, detached, or fully covered.
    private var shouldAnimate: Bool {
        guard !isStopped, let window else { return false }
        return !pausesWhenOccluded || window.occlusionState.contains(.visible)
    }

    override func animateOneFrame() {
        guard shouldAnimate else { return }
        if let tank = currentTank() {
            tank.aquarium.step()
            needsDisplay = true
        }
    }

    // MARK: Drawing

    override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let tank = isStopped ? nil : currentTank()
        if let tank {
            backgroundRenderer.surfaceInset = surfaceInset(for: tank.layout)
        }
        backgroundRenderer.draw(settings.background, in: bounds, ctx: ctx)
        if let tank {
            tank.renderer.draw(tank.aquarium.render(), layout: tank.layout, in: ctx)
        }
    }

    /// Distance from the top of the view to the top of the water line (grid row 5).
    private func surfaceInset(for layout: GridLayout) -> CGFloat {
        let gridTop = layout.origin.y + CGFloat(layout.rows) * layout.cellSize.height
        return bounds.height - gridTop + 5 * layout.cellSize.height
    }

    // MARK: Layout

    /// The tank for the current size and settings, rebuilt with a fresh seed when either changed.
    private func currentTank() -> Tank? {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return nil }
        if let tank, tank.size == size, tank.settings == settings { return tank }

        let pointSize = CGFloat(settings.textSize.pointSize)
        let fullSize = GridRenderer(pointSize: pointSize, palette: .terminal)
        let renderer: GridRenderer
        let layout: GridLayout
        if isPreview {
            // Show the main screen's full-size tank, scaled down to the thumbnail.
            let screenSize = NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)
            let reference = GridLayout.fit(viewSize: screenSize, cellSize: fullSize.cellSize)
            let cell = fullSize.cellSize
            layout = GridLayout.preview(
                viewSize: size,
                referenceCols: reference.cols,
                referenceRows: reference.rows,
                cellAspect: cell.height / cell.width
            ).layout
            renderer = GridRenderer(pointSize: pointSize * layout.cellSize.width / cell.width, palette: .terminal)
        } else {
            renderer = fullSize
            layout = GridLayout.fit(viewSize: size, cellSize: fullSize.cellSize)
        }

        let aquarium = Aquarium(
            cols: layout.cols,
            rows: layout.rows,
            settings: settings,
            seed: UInt64.random(in: .min ... .max)
        )
        log.debug("new tank \(layout.cols)x\(layout.rows) preview=\(self.isPreview)")
        let tank = Tank(size: size, settings: settings, renderer: renderer, layout: layout, aquarium: aquarium)
        self.tank = tank
        return tank
    }
}
