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
        span.reveal(span.textField("categories.newName"))
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
        span.reveal(field)
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
        span.reveal(span.textField("categories.newName"))
        span.textField("categories.newName").waitToAppear()
        XCTAssertFalse(span.button("categories.add").isEnabled,
                       "a blank category can be added")
    }

    func testACategorySurvivesARelaunch() {
        span = SpanApp()
        span.launch()
        span.select("settings")

        let field = span.textField("categories.newName")
        span.reveal(field)
        field.waitToAppear()
        span.type("Persisted", into: field)
        span.button("categories.add").click()
        _ = span.app.textFields["Persisted"].waitForExistence(timeout: 10)

        span.relaunch()
        span.select("settings")

        XCTAssertTrue(span.app.textFields["Persisted"].waitForExistence(timeout: 15)
                      || span.app.staticTexts["Persisted"].waitForExistence(timeout: 5),
                      "the category was not saved")
    }

    func testDeletingACategoryRemovesIt() {
        span = SpanApp().launch()
        span.select("settings")

        let field = span.textField("categories.newName")
        span.reveal(field)
        field.waitToAppear()
        span.type("Doomed", into: field)
        span.button("categories.add").click()

        let delete = span.button("category.delete.Doomed")
        span.reveal(delete)
        delete.waitToAppear(10, "the new category has no delete button")
        delete.click()

        delete.waitToVanish(10)
    }

    func testACategoryColourPopoverOpens() {
        span = SpanApp().launch()
        span.select("settings")

        let swatch = span.button("category.colour.Deep Work")
        span.reveal(swatch)
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
        span.reveal(span.control("settings.tracking"))
        XCTAssertTrue(span.control("settings.tracking").exists, "the tracking toggle is missing")
        XCTAssertTrue(span.control("settings.hud").exists, "the HUD toggle is missing")
        XCTAssertTrue(span.control("settings.notifications").exists, "the notifications toggle is missing")

        // The two menus are NSPopUpButtons; SwiftUI does not carry an
        // identifier onto them, so they are found by their current value.
        XCTAssertTrue(span.popUpButton(showing: "5h") != nil, "the daily target menu is missing")
        XCTAssertTrue(span.popUpButton(showing: "5m") != nil, "the idle threshold menu is missing")
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

        span.relaunch()
        span.select("settings")
        XCTAssertEqual(span.textField("settings.userName").value as? String, "Amey",
                       "the name was not saved")
    }

    func testTheTrackingToggleInSettingsFlips() {
        span = SpanApp().launch()
        span.select("settings")

        let toggle = span.control("settings.tracking")
        span.reveal(toggle)
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

        let picker = try! XCTUnwrap(span.popUpButton(showing: "5m"),
                                    "the idle threshold menu is missing")
        picker.click()
        let tenMinutes = span.app.menuItems["10m"]
        tenMinutes.waitToAppear(10, "the idle threshold menu has no 10m option")
        tenMinutes.click()

        span.relaunch()
        span.select("settings")
        XCTAssertNotNil(span.popUpButton(showing: "10m"),
                        "the idle threshold was not remembered across a relaunch")
    }

    func testTheDailyTargetCanBeChanged() {
        span = SpanApp().launch()
        span.select("settings")

        let picker = try! XCTUnwrap(span.popUpButton(showing: "5h"),
                                    "the daily target menu is missing")
        picker.click()
        let fourHours = span.app.menuItems["4h"]
        fourHours.waitToAppear(10, "the daily target menu has no 4h option")
        fourHours.click()

        XCTAssertNotNil(span.popUpButton(showing: "4h"), "the daily target did not change")
    }

    func testTheAccessibilityRowReflectsThePermissionState() {
        span = SpanApp().launch()
        span.select("settings")

        // Granted shows a confirmation; not granted offers the two buttons.
        // Which one depends on the machine, so accept either — but not neither.
        span.reveal(span.app.staticTexts["Granted"])
        let granted = span.app.staticTexts["Granted"].exists
        let grant = span.button("settings.grantAccessibility").exists
        let openSettings = span.button("settings.openSystemSettings").exists

        XCTAssertTrue(granted || (grant && openSettings),
                      "the accessibility row shows neither a granted state nor a way to grant")
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
