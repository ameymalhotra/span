import XCTest

@MainActor
final class ToolbarAndShortcutsUITests: XCTestCase {

    private var span: SpanApp!

    override func setUp() { continueAfterFailure = false }
    override func tearDown() { span?.terminate(); span = nil }

    func testCommandNOpensTheNewSessionSheet() {
        span = SpanApp().launch()
        span.pressShortcut("n")
        span.textField("startSession.title").waitToAppear(10, "⌘N did not open the new-session sheet")
        span.button("startSession.cancel").click()
    }

    func testCommandBAddsABlockAndOpensItsEditor() {
        span = SpanApp().launch()
        span.pressShortcut("b")
        span.textField("entryEditor.title").waitToAppear(10, "⌘B did not open the block editor")
    }

    func testTheAddBlockToolbarButtonMatchesTheShortcut() {
        span = SpanApp().launch()
        let add = span.button("toolbar.addBlock")
        add.waitToAppear(10, "the Add Block toolbar button is missing")
        add.click()
        span.textField("entryEditor.title").waitToAppear(10, "Add Block did not open the editor")
    }

    func testDayNavigationMovesBackwardsAndForwards() {
        span = SpanApp().launch()

        let previous = span.button("toolbar.previousDay")
        let next = span.button("toolbar.nextDay")
        previous.waitToAppear(10, "the day navigation buttons are missing")

        XCTAssertFalse(next.isEnabled, "the app allows navigating into the future from today")

        previous.click()
        XCTAssertTrue(next.isEnabled, "Next stayed disabled after moving to yesterday")

        next.click()
        XCTAssertFalse(next.isEnabled, "Next should be disabled again back on today")
    }

    func testTheBracketShortcutsNavigateDays() {
        span = SpanApp().launch()
        let next = span.button("toolbar.nextDay")
        next.waitToAppear()
        XCTAssertFalse(next.isEnabled)

        span.pressShortcut("[")
        let enabled = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: enabled, object: next)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed,
                       "⌘[ did not move to the previous day")

        span.pressShortcut("]")
        let disabled = NSPredicate(format: "isEnabled == false")
        let back = XCTNSPredicateExpectation(predicate: disabled, object: next)
        XCTAssertEqual(XCTWaiter().wait(for: [back], timeout: 5), .completed,
                       "⌘] did not return to today")
    }

    func testCommandTReturnsToToday() {
        span = SpanApp().launch()
        let next = span.button("toolbar.nextDay")
        next.waitToAppear()

        span.button("toolbar.previousDay").click()
        span.button("toolbar.previousDay").click()
        XCTAssertTrue(next.isEnabled)

        span.pressShortcut("t")
        let disabled = NSPredicate(format: "isEnabled == false")
        let expectation = XCTNSPredicateExpectation(predicate: disabled, object: next)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed,
                       "⌘T did not return to today")
    }

    func testTheDateNavigatorOpensAPickerWithATodayShortcut() {
        span = SpanApp().launch()
        let navigator = span.control("dateNavigator.button")
        navigator.waitToAppear(10, "the date navigator button is missing")

        span.button("toolbar.previousDay").click()
        navigator.click()

        let today = span.button("dateNavigator.today")
        today.waitToAppear(10, "the popover has no Today button when off today")
        today.click()

        let next = span.button("toolbar.nextDay")
        let disabled = NSPredicate(format: "isEnabled == false")
        let expectation = XCTNSPredicateExpectation(predicate: disabled, object: next)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5),
                       .completed, "the popover's Today button did not return to today")
    }

    func testTheTodayButtonIsHiddenWhileAlreadyOnToday() {
        span = SpanApp().launch()
        let navigator = span.control("dateNavigator.button")
        navigator.waitToAppear()
        navigator.click()
        XCTAssertFalse(span.button("dateNavigator.today").waitForExistence(timeout: 2),
                       "the Today button is offered while already on today")
        span.app.typeKey(.escape, modifierFlags: [])
    }

    func testTheZoomMenuOffersFourScales() {
        span = SpanApp().launch()
        let zoom = span.control("toolbar.zoom")
        zoom.waitToAppear(10, "the timeline zoom control is missing")
        zoom.click()

        for scale in ["Compact", "Default", "Comfortable", "Expanded"] {
            XCTAssertTrue(span.app.menuItems[scale].exists || span.app.buttons[scale].exists,
                          "the zoom menu is missing \(scale)")
        }
        span.app.typeKey(.escape, modifierFlags: [])
    }

    func testChoosingAZoomScaleIsAccepted() {
        span = SpanApp().launch()
        let zoom = span.control("toolbar.zoom")
        zoom.waitToAppear()
        zoom.click()

        let expanded = span.app.menuItems["Expanded"].exists
            ? span.app.menuItems["Expanded"] : span.app.buttons["Expanded"]
        if expanded.waitForExistence(timeout: 5) {
            expanded.click()
        }
        span.window.waitToAppear()
    }
}
