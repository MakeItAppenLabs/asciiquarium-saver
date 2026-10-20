import Foundation
import Synchronization

/// One step of a scripted movement path (Perl: an element of `callback_args->[1]`).
public struct PathStep: Sendable, Equatable {
    public var dx: Double
    public var dy: Double
    /// Absolute frame to show, not an increment. `nil` leaves the frame alone.
    public var frame: Double?

    public init(dx: Double, dy: Double, frame: Double? = nil) {
        self.dx = dx
        self.dy = dy
        self.frame = frame
    }
}

/// A sprite on the screen: Term::Animation::Entity.
///
/// Callbacks mutate the entity directly. Perl's callbacks instead return `(x, y, z, frame)` for the
/// engine to apply, which a Swift closure has no need for.
public final class Entity {
    private static let nextID = Mutex(0)

    public let id: Int

    /// Perl's `type`: `"fish"`, `"shark"`, `"teeth"`, `"waterline"`, ...
    public var type: String

    /// Changing the sprite updates `width` and `height`.
    public var sprite: Sprite {
        didSet { size = (sprite.width, sprite.height) }
    }
    private var size: (width: Int, height: Int)

    /// Used for every sprite cell that has no color of its own.
    public var defaultColor: CellColor

    public var x: Double
    public var y: Double
    /// Lower z draws in front.
    public var z: Int

    /// Per-step movement of the default move (Perl `callback_args` `[dx, dy, dz, frame_speed]`).
    public var dx: Double
    public var dy: Double
    /// Added to `frame` each step by the default move. Zero leaves the frame alone.
    public var frameSpeed: Double
    /// Current animation frame. May be fractional; the sprite frame shown is `floor(frame)`.
    public var frame: Double

    /// A scripted path that the default move follows instead of `dx`, `dy` and `frameSpeed`, one step
    /// per tick, wrapping from the last step to the first (Perl `callback_args` `[index, [steps]]`).
    public var path: [PathStep] = []
    public var pathIndex = 0

    /// Perl `die_offscreen`. See `Engine.step()` for the exact rule.
    public var dieOffscreen: Bool
    /// Perl `die_time`, in engine steps. The entity is removed during its Nth step, before it ticks.
    /// To convert Perl seconds at the app's 10 steps per second use `Int(seconds * 10)`.
    public var dieAfterFrames: Int?
    /// Perl `die_frame`: the entity ticks and is drawn N times, then is removed in step N + 1. The engine
    /// counts it down, as Perl does.
    public var dieAfterCycles: Int?

    /// Perl `physical`: takes part in collision detection.
    public var isPhysical: Bool
    /// Perl `depth`: the entity occupies z in `z ..< z + depth` for collisions. Not used for drawing.
    public var depth: Int

    /// Replaces the default move when set. Call `defaultMove()` from inside to keep it.
    public var onTick: ((Entity, Engine) -> Void)?
    /// Called with every other physical entity that overlaps this one, when there is at least one.
    public var onCollision: ((Entity, [Entity], Engine) -> Void)?
    /// Called once when the entity is killed, before it leaves the engine. Not called by `Engine.remove`.
    public var onDeath: ((Entity, Engine) -> Void)?

    /// Entity-wide size: the largest frame, as in Perl.
    public var width: Int { size.width }
    public var height: Int { size.height }

    enum Lifecycle {
        case detached
        case active
        /// A kill is queued; the entity stays in the engine until the removal phase.
        case dying
    }
    var lifecycle = Lifecycle.detached
    /// Steps started since the entity joined the engine, for `dieAfterFrames`.
    var age = 0

    /// True from `Engine.add` until the entity is killed or removed.
    public var isAlive: Bool { lifecycle == .active }

    public init(
        type: String = "self",
        sprite: Sprite,
        x: Double = 0,
        y: Double = 0,
        z: Int = 0,
        dx: Double = 0,
        dy: Double = 0,
        frameSpeed: Double = 0,
        frame: Double = 0,
        defaultColor: CellColor = CellColor(color: .white, bright: false),
        depth: Int = 1,
        isPhysical: Bool = false,
        dieOffscreen: Bool = false,
        dieAfterFrames: Int? = nil,
        dieAfterCycles: Int? = nil
    ) {
        self.id = Entity.nextID.withLock { value in
            value += 1
            return value
        }
        self.type = type
        self.sprite = sprite
        self.size = (sprite.width, sprite.height)
        self.x = x
        self.y = y
        self.z = z
        self.dx = dx
        self.dy = dy
        self.frameSpeed = frameSpeed
        self.frame = frame
        self.defaultColor = defaultColor
        self.depth = depth
        self.isPhysical = isPhysical
        self.dieOffscreen = dieOffscreen
        self.dieAfterFrames = dieAfterFrames
        self.dieAfterCycles = dieAfterCycles
    }

    /// Term::Animation::Entity `move_entity`.
    ///
    /// With a `path`, applies the current step, advances (wrapping) and sets the frame to the step's
    /// absolute frame. Otherwise adds `dx`, `dy` and, when `frameSpeed` is nonzero, `frameSpeed` to the
    /// frame: the fractional part is kept and the whole part wraps around the frame count.
    public func defaultMove() {
        if !path.isEmpty {
            let step = path[pathIndex % path.count]
            pathIndex = (pathIndex + 1) % path.count
            x += step.dx
            y += step.dy
            if let f = step.frame { frame = f }
            return
        }
        x += dx
        y += dy
        if frameSpeed != 0 {
            let f = frame + frameSpeed
            let whole = f.rounded(.towardZero)
            let count = max(1, sprite.frames.count)
            let wrapped = ((Int(whole) % count) + count) % count
            frame = (f - whole) + Double(wrapped)
        }
    }
}
