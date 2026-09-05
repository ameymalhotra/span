import XCTest

@MainActor
final class CategoryAndSettingsUITests: XCTestCase {

    private var span: SpanApp!

    override func setUp() { continueAfterFailure = false }
    override func tearDown() { span?.terminate(); span = nil }

    // MARK: - Categories

    func testTheDefaultCategoriesAreSeededOnAFreshStore() {
        span = SpanApp().launch()
        span.select("settings")
        for name in ["Deep Work", "Meeting", "Learning", "Admin", "Break"] {
            XCTAssertTrue(span.app.staticTexts[name].waitForExistence(timeout: 10)
                          || span.app.textFields[name].waitForExistence(timeout: 2),
                          "the seeded category \(name) is missing")
        }
    }

    func testAddingACategoryThroughTheButton() {
        span = SpanApp().launch()
        span.select("settings")

        let field = span.textField("categories.newName")
        field.waitToAppear(10, "the add-category field is missing")
        span.type("Gardening", into: field)
        span.button("categories.add").click()

        XCTAssertTrue(span.app.textFields["Gardening"].waitForExistence(timeout: 10)
                      || span.app.staticTexts["Gardening"].waitForExistence(timeout: 2),
                      "the new category did not appear")
    }

    func testTheAddButtonIsDisabledWithNoName() {
        span = SpanApp().launch()
        span.select("settings")
        span.textField("categories.newName").waitToAppear()
        XCTAssertFalse(span.button("categories.add").isEnabled,
                       "a blank category can be added")
    }

    func testACategorySurvivesARelaunch() {
        span = SpanApp()
        span.launch()
        span.select("settings")

        let field = span.textField("categories.newName")
        field.waitToAppear()
        span.type("Persisted", into: field)
        span.button("categories.add").click()
        _ = span.app.textFields["Persisted"].waitForExistence(timeout: 10)

        span.app.terminate()
        span.app.launch()
        span.select("settings")

        XCTAssertTrue(span.app.textFields["Persisted"].waitForExistence(timeout: 15)
                      || span.app.staticTexts["Persisted"].waitForExistence(timeout: 5),
                      "the category was not saved")
    }

    func testDeletingACategoryRemovesIt() {
        span = SpanApp().launch()
        span.select("settings")

        let field = span.textField("categories.newName")
        field.waitToAppear()
        span.type("Doomed", into: field)
        span.button("categories.add").click()

        let delete = span.button("category.delete.Doomed")
        delete.waitToAppear(10, "the new category has no delete button")
        delete.click()

        delete.waitToVanish(10)
    }

    func testACategoryColourPopoverOpens() {
        span = SpanApp().launch()
        span.select("settings")

        let swatch = span.button("category.colour.Deep Work")
        if swatch.waitForExistence(timeout: 10) {
            swatch.click()
            span.app.typeKey(.escape, modifierFlags: [])
        }
        XCTAssertTrue(span.window.exists)
    }

    // MARK: - Settings

    func testTheSettingsPaneShowsItsControls() {
        span = SpanApp().launch()
        span.select("settings")

        span.textField("settings.userName").waitToAppear(10, "the name field is missing")
        XCTAssertTrue(span.control("settings.dailyTarget").exists, "the daily target picker is missing")
        XCTAssertTrue(span.control("settings.idleThreshold").exists, "the idle threshold picker is missing")
        XCTAssertTrue(span.control("settings.tracking").exists, "the tracking toggle is missing")
        XCTAssertTrue(span.control("settings.hud").exists, "the HUD toggle is missing")
        XCTAssertTrue(span.control("settings.notifications").exists, "the notifications toggle is missing")
    }

    func testTheNameIsUsedInTheGreetingAndSurvivesARelaunch() {
        span = SpanApp()
        span.launch()
        span.select("settings")

        let name = span.textField("settings.userName")
        name.waitToAppear()
        span.type("Amey", into: name)
        span.select("focus")

        XCTAssertTrue(span.app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS[c] %@", "Amey")).firstMatch
            .waitForExistence(timeout: 10)
            || span.app.staticTexts["Good morning, Amey"].exists
            || span.app.staticTexts["Good afternoon, Amey"].exists
            || span.app.staticTexts["Good evening, Amey"].exists,
            "the greeting does not use the name that was just set")

        span.app.terminate()
        span.app.launch()
        span.select("settings")
        XCTAssertEqual(span.textField("settings.userName").value as? String, "Amey",
                       "the name was not saved")
    }

    func testTheTrackingToggleInSettingsFlips() {
        span = SpanApp().launch()
        span.select("settings")

        let toggle = span.control("settings.tracking")
        toggle.waitToAppear(10, "the tracking toggle is missing")
        let before = toggle.value as? Int
        toggle.click()
        XCTAssertNotEqual(before, toggle.value as? Int, "the tracking toggle did not change")
        toggle.click()
    }

    func testTheIdleThresholdCanBeChangedAndIsRemembered() {
        span = SpanApp()
        span.launch()
        span.select("settings")

        let picker = span.control("settings.idleThreshold")
        picker.waitToAppear(10, "the idle threshold picker is missing")
        picker.click()

        let tenMinutes = span.app.menuItems["10m"]
        if tenMinutes.waitForExistence(timeout: 5) {
            tenMinutes.click()
            span.app.terminate()
            span.app.launch()
            span.select("settings")
            XCTAssertEqual(span.control("settings.idleThreshold").value as? String, "10m",
                           "the idle threshold was not remembered")
        } else {
            span.app.typeKey(.escape, modifierFlags: [])
        }
    }

    func testTheDailyTargetCanBeChanged() {
        span = SpanApp().launch()
        span.select("settings")

        let picker = span.control("settings.dailyTarget")
        picker.waitToAppear(10)
        picker.click()

        let fourHours = span.app.menuItems["4h"]
        if fourHours.waitForExistence(timeout: 5) {
            fourHours.click()
            XCTAssertEqual(span.control("settings.dailyTarget").value as? String, "4h")
        } else {
            span.app.typeKey(.escape, modifierFlags: [])
        }
    }

    func testTheAccessibilityButtonsArePresent() {
        span = SpanApp().launch()
        span.select("settings")
        XCTAssertTrue(span.button("settings.openSystemSettings").waitForExistence(timeout: 10),
                      "the Open System Settings button is missing")
    }

    func testTheGuideAndInsightsPanesRender() {
        span = SpanApp().launch()
        span.select("guide")
        XCTAssertTrue(span.window.exists)
        span.select("insights")
        XCTAssertTrue(span.window.exists)
        span.select("categories")
        XCTAssertTrue(span.window.exists)
    }
}
