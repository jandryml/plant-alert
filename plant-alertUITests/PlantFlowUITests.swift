//
//  PlantFlowUITests.swift
//  plant-alertUITests
//

import XCTest

/// Smoke test for the core loop: add a plant, water it, open its detail.
final class PlantFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The app asks for notification permission on first launch; the system
    /// alert belongs to Springboard, not the app.
    private func dismissNotificationPrompt() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 8) {
            allow.tap()
        }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testAddWaterAndInspectPlant() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        dismissNotificationPrompt()

        // Empty state
        let addFirst = app.buttons["Add a plant"]
        XCTAssertTrue(addFirst.waitForExistence(timeout: 10), "empty state should offer to add a plant")
        attach(app, "01-empty")

        addFirst.tap()

        // Editor
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "editor should show a name field")
        nameField.tap()
        nameField.typeText("Monstera")

        let roomField = app.textFields["Room (optional)"]
        if roomField.exists {
            roomField.tap()
            roomField.typeText("Living room")
        }
        XCTAssertTrue(
            app.buttons["Choose photo"].exists,
            "the editor should offer to attach a photo"
        )
        attach(app, "02-editor")

        app.buttons["Save"].tap()

        // List
        let card = app.staticTexts["Monstera"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the new plant should appear in the list")
        XCTAssertTrue(app.staticTexts["Needs water"].exists, "a never-watered plant belongs in Needs water")
        attach(app, "03-list")

        // Water it — it should move out of the thirsty section.
        app.buttons["Water this plant"].firstMatch.tap()
        XCTAssertTrue(
            app.staticTexts["Coming up"].waitForExistence(timeout: 5),
            "after watering, the plant should move to Coming up"
        )
        attach(app, "04-after-watering")

        // Detail
        card.tap()
        XCTAssertTrue(app.buttons["Water now"].waitForExistence(timeout: 5), "detail should offer Water now")
        XCTAssertTrue(app.staticTexts["History"].exists, "detail should show a history section")
        attach(app, "05-detail")
    }

    func testSettingsOpens() throws {
        let app = XCUIApplication()
        app.launch()
        dismissNotificationPrompt()

        app.buttons["Settings"].tap()

        // Form section headers render uppercased, so assert on controls instead.
        XCTAssertTrue(
            app.switches["Daily reminder"].waitForExistence(timeout: 5),
            "settings should show the reminder toggle"
        )
        XCTAssertEqual(
            app.buttons["Time Picker"].value as? String, "09:00",
            "the digest should default to 9am"
        )
        attach(app, "06-settings")

        // The sharing section is below the fold in a lazily rendered Form.
        let syncButton = app.buttons["Sync now"]
        for _ in 0..<4 where !syncButton.exists {
            app.swipeUp()
        }
        XCTAssertTrue(syncButton.waitForExistence(timeout: 5), "sharing section should offer Sync now")
        XCTAssertFalse(syncButton.isEnabled, "Sync now stays disabled until Supabase is configured")
        attach(app, "07-sharing")

        // Regression guard: this link once sat on the bottom edge, where the
        // home indicator's gesture area swallowed taps on it.
        let guideLink = app.buttons["How to set up Supabase"]
        XCTAssertTrue(guideLink.waitForExistence(timeout: 5), "the setup guide link should be reachable")
        guideLink.tap()
        XCTAssertTrue(
            app.staticTexts["Supabase Setup"].waitForExistence(timeout: 5),
            "the setup guide should open"
        )
        attach(app, "08-setup-guide")
    }

    /// The photo viewer, driven against a seeded plant so the system photo
    /// picker never has to be involved.
    func testTappingPhotoOpensItFullScreen() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSeedPhoto"]
        app.launch()
        dismissNotificationPrompt()

        let card = app.staticTexts["Photo Plant"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "the seeded plant should be listed")
        attach(app, "09-list-with-photo")

        card.tap()

        let avatar = app.buttons["Photo of Photo Plant"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 5), "the photo should be a tappable button on detail")
        attach(app, "10-detail-with-photo")

        avatar.tap()

        let close = app.buttons["Close photo"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "tapping the photo should open it full screen")
        attach(app, "11-photo-full-screen")

        close.tap()
        XCTAssertTrue(
            app.buttons["Water now"].waitForExistence(timeout: 5),
            "closing the photo should return to the plant"
        )
    }
}
