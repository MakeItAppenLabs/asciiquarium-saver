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

    func testPlayPauseOpensOptionsAndBackClosesThem() {
        let app = XCUIApplication()
        app.launch()
        sleep(1)
        remote.press(.playPause)
        XCTAssertTrue(app.staticTexts["Options"].waitForExistence(timeout: 3))
        sleep(1)
        snapshot("options-open")
        remote.press(.menu)
        sleep(1)
        XCTAssertFalse(app.staticTexts["Options"].exists)
        XCTAssertEqual(app.state, .runningForeground)
        snapshot("options-closed")
    }

    /// Picks Classic, closes the panel, relaunches, and finds Classic still chosen; then puts Full back.
    func testAChangeIsKeptAcrossLaunches() {
        let app = XCUIApplication()
        app.launch()
        sleep(1)
        choose(creatureSet: "Classic", in: app)
        snapshot("classic-chosen")
        remote.press(.menu)
        app.terminate()

        app.launch()
        sleep(1)
        remote.press(.playPause)
        XCTAssertTrue(app.staticTexts["Options"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons.matching(identifier: "Classic").firstMatch.isSelected)
        remote.press(.menu)
        sleep(1)
        choose(creatureSet: "Full", in: app)
        remote.press(.menu)
    }

    /// Opens Options, moves down to Creature set (Full, Classic) and picks `name`.
    private func choose(creatureSet name: String, in app: XCUIApplication) {
        remote.press(.playPause)
        XCTAssertTrue(app.staticTexts["Options"].waitForExistence(timeout: 3))
        sleep(1)
        remote.press(.down)
        remote.press(name == "Classic" ? .right : .left)
        remote.press(.select)
        sleep(1)
        XCTAssertTrue(app.buttons.matching(identifier: name).firstMatch.isSelected)
    }

    /// Back from each sub-screen returns to the panel's top, and keeps screenshots to check by eye.
    func testBackFromASubScreenReturnsToOptions() {
        let app = XCUIApplication()
        app.launch()
        sleep(1)
        remote.press(.playPause)
        XCTAssertTrue(app.staticTexts["Options"].waitForExistence(timeout: 3))
        sleep(1)
        snapshot("panel")
        for (name, title) in [("Special creatures", "Special creatures"), ("Background", "Background"), ("Credits", "Credits")] {
            let row = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            for _ in 0..<8 where !row.hasFocus { remote.press(.down) }
            XCTAssertTrue(row.hasFocus, "never reached \(name)")
            remote.press(.select)
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 3))
            sleep(1)
            snapshot(name)
            if name == "Credits" {
                // The GPL asks for the source address to be reachable: scroll to the last paragraph.
                let source = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Source code'")).firstMatch
                for _ in 0..<12 where !source.hasFocus { remote.press(.down) }
                XCTAssertTrue(source.hasFocus)
                XCTAssertTrue(source.isHittable)
                snapshot("Credits-end")
            }
            remote.press(.menu)
            sleep(1)
            XCTAssertTrue(app.staticTexts["Options"].exists, "Back from \(name) should return to Options, not close it")
        }
        remote.press(.menu)
    }
}
