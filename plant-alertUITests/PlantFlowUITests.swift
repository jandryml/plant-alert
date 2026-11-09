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

    func testAddWaterAndInspectPlant() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        // The app asks for notification permission on first launch; the system
        // alert belongs to Springboard, not the app.
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 8) {
            allow.tap()
        }

        let addFirst = app.buttons["Add a plant"]
        XCTAssertTrue(addFirst.waitForExistence(timeout: 10), "empty state should offer to add a plant")
        addFirst.tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "editor should show a name field")
        nameField.tap()
        nameField.typeText("Monstera")
        app.buttons["Save"].tap()

        let card = app.staticTexts["Monstera"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the new plant should appear in the list")
        XCTAssertTrue(app.staticTexts["Needs water"].exists, "a never-watered plant belongs in Needs water")

        app.buttons["Water this plant"].firstMatch.tap()
        XCTAssertTrue(
            app.staticTexts["Coming up"].waitForExistence(timeout: 5),
            "after watering, the plant should move to Coming up"
        )

        card.tap()
        XCTAssertTrue(app.buttons["Water now"].waitForExistence(timeout: 5), "detail should offer Water now")
    }
}
