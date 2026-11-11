import UIKit
import AquariumKit

/// Draws the tank edge to edge: the background, then the character grid.
final class TankView: UIView {
    private(set) var settings: AquariumSettings

    /// Everything that depends on the view size and settings, rebuilt together.
    private struct Tank {
        var size: CGSize
        var settings: AquariumSettings
        var renderer: GridRenderer
        var layout: GridLayout
        var aquarium: Aquarium
    }

    private var tank: Tank?
    private let backgroundRenderer = BackgroundRenderer()

    /// The tank's aquarium, built now if no frame has been drawn yet (just after launch or a settings
    /// change), so a click in that moment still reaches it.
    var aquarium: Aquarium? { currentTank()?.aquarium }

    init(settings: AquariumSettings) {
        self.settings = settings
        super.init(frame: .zero)
        isOpaque = true
        backgroundColor = .black
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Advances the animation one frame.
    func step() {
        guard let tank = currentTank() else { return }
        tank.aquarium.step()
        setNeedsDisplay()
    }

    /// Adopts new settings. A background change only repaints; anything else rebuilds the tank, as the
    /// Mac saver does, because an `Aquarium` keeps its settings for life.
    func apply(_ new: AquariumSettings) {
        var sameBackground = new
        sameBackground.background = settings.background
        settings = new
        if let current = tank, sameBackground == current.settings {
            tank?.settings = new
        } else {
            tank = nil
        }
        setNeedsDisplay()
    }

    // MARK: Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        // UIKit's context is flipped; the renderers draw unflipped, with row 0 at the top, as on the Mac.
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)

        let tank = currentTank()
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

        let renderer = GridRenderer(pointSize: settings.textSize.tvPointSize, palette: .terminal)
        let layout = GridLayout.fit(viewSize: size, cellSize: renderer.cellSize)
        let aquarium = Aquarium(
            cols: layout.cols,
            rows: layout.rows,
            settings: settings,
            seed: UInt64.random(in: .min ... .max)
        )
        let tank = Tank(size: size, settings: settings, renderer: renderer, layout: layout, aquarium: aquarium)
        self.tank = tank
        return tank
    }
}
