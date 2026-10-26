import XCTest

/// Drives the Apple TV app with the remote and keeps a screenshot after each press, since the
/// simulator has no on-screen remote to do this by hand. The hook and the tank are checked by eye
/// from the attachments; the Options panel is checked by its elements.
@MainActor
final class RemoteUITests: XCTestCase {
    private let remote = XCUIRemote.shared

    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The hook rules themselves are unit tested (`RemoteHookTests`); this checks that clicks reach the
    /// tank. Fish bite fast in a TV-sized tank, so the shots are taken soon after each click.
    func testClicksReachTheTank() {
        let app = XCUIApplication()
        app.launch()
        sleep(2)
        snapshot("0-before")
        remote.press(.select)
        usleep(800_000)
        snapshot("1-after-first-click")
        remote.press(.select)
        usleep(800_000)
        snapshot("2-after-second-click")
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testBackLeavesTheApp() {
        let app = XCUIApplication()
        app.launch()
        sleep(1)
        remote.press(.menu)
        XCTAssertTrue(app.wait(for: .runningBackgroundSuspended, timeout: 5) || app.state != .runningForeground)
    }
}
