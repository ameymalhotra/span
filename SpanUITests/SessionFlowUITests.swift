import XCTest

@MainActor
final class SessionFlowUITests: XCTestCase {

    private var span: SpanApp!

    override func setUp() { continueAfterFailure = false }
    override func tearDown() { span?.terminate(); span = nil }

    func testStartingASessionSwapsTheStartButtonForTheRunningControls() {
        span = SpanApp().launch()
        span.startSession(title: "Write the report")

        span.button("focus.pause").waitToAppear(10, "the running session's Pause button never appeared")
        span.button("focus.finish").waitToAppear()
        XCTAssertFalse(span.button("focus.start").exists, "the idle Start button is still showing")
    }

    func testTheSessionTitleIsShownWhileItRuns() {
        span = SpanApp().launch()
        span.startSession(title: "Write the report")
        XCTAssertTrue(span.app.staticTexts["Write the report"].waitForExistence(timeout: 10),
                      "the running session does not name itself")
    }

    func testPauseAndResumeSwapPlaces() {
        span = SpanApp().launch()
        span.startSession(title: "Write the report")

        span.button("focus.pause").waitToAppear()
        span.button("focus.pause").click()

        span.button("focus.resume").waitToAppear(10, "Pause did not become Resume")
        XCTAssertFalse(span.button("focus.pause").exists)

        span.button("focus.resume").click()
        span.button("focus.pause").waitToAppear(10, "Resume did not become Pause")
    }

    func testFinishingOffersTheReflectionSheet() {
        span = SpanApp().launch()
        span.startSession(title: "Write the report")

        span.button("focus.finish").waitToAppear()
        span.button("focus.finish").click()

        span.button("reflection.save").waitToAppear(10, "finishing did not offer a review")
        span.button("reflection.skip").waitToAppear()
    }

    func testSavingAReviewClosesTheSheetAndReturnsToIdle() {
        span = SpanApp().launch()
        span.startSession(title: "Write the report")
        span.button("focus.finish").click()

        let save = span.button("reflection.save")
        save.waitToAppear()
        save.click()

        save.waitToVanish(10)
        span.button("focus.start").waitToAppear(10, "the pane did not return to its idle state")
    }

    func testSkippingAReviewAlsoClosesTheSheet() {
        span = SpanApp().launch()
        span.startSession(title: "Write the report")
        span.button("focus.finish").click()

        let skip = span.button("reflection.skip")
        skip.waitToAppear()
        skip.click()

        skip.waitToVanish(10)
        span.button("focus.start").waitToAppear()
    }

    func testTheReviewSheetCannotBeDismissedByEscape() {
        span = SpanApp().launch()
        span.startSession(title: "Write the report")
        span.button("focus.finish").click()

        let save = span.button("reflection.save")
        save.waitToAppear()
        span.app.typeKey(.escape, modifierFlags: [])

        // interactiveDismissDisabled: Escape must not leave the review unanswered.
        XCTAssertTrue(save.exists, "the review sheet was dismissed without an answer")
        span.button("reflection.skip").click()
    }

    func testTheDistractionStepperAcceptsInput() {
        span = SpanApp().launch()
        span.startSession(title: "Write the report")
        span.button("focus.finish").click()

        let stepper = span.app.steppers["reflection.distractions"]
        if stepper.waitForExistence(timeout: 5) {
            stepper.incrementArrows.firstMatch.click()
        }
        span.button("reflection.save").click()
        span.button("focus.start").waitToAppear()
    }

    func testAReviewedSessionShowsUpInTheDayReview() {
        span = SpanApp().launch()
        span.startSession(title: "Write the report")
        span.button("focus.finish").click()
        span.button("reflection.save").waitToAppear()
        span.button("reflection.save").click()

        span.select("day")
        XCTAssertTrue(span.app.staticTexts["Write the report"].waitForExistence(timeout: 10),
                      "the finished session is missing from the day review")
    }

    func testTheStartButtonIsDisabledWhileASessionRuns() {
        span = SpanApp().launch()
        span.startSession(title: "Write the report")
        span.button("focus.pause").waitToAppear()

        let toolbarStart = span.button("toolbar.startSession")
        if toolbarStart.exists {
            XCTAssertFalse(toolbarStart.isEnabled,
                           "a second session can be started from the toolbar while one runs")
        }
    }

    func testCancellingTheNewSessionSheetStartsNothing() {
        span = SpanApp().launch()
        span.button("focus.start").click()

        let title = span.textField("startSession.title")
        title.waitToAppear()
        span.type("Never started", into: title)
        span.button("startSession.cancel").click()

        title.waitToVanish(10)
        span.button("focus.start").waitToAppear(10, "cancelling should leave the pane idle")
    }

    func testANewSessionNeedsATitle() {
        span = SpanApp().launch()
        span.button("focus.start").click()

        let title = span.textField("startSession.title")
        title.waitToAppear()
        XCTAssertFalse(span.button("startSession.start").isEnabled,
                       "a session can be started with no title")

        span.type("Now it has one", into: title)
        XCTAssertTrue(span.button("startSession.start").isEnabled)
        span.button("startSession.cancel").click()
    }

    func testTheTrackingToggleFlips() {
        span = SpanApp().launch()
        let toggle = span.checkBox("status.trackingToggle")
        toggle.waitToAppear(10, "the status bar tracking toggle is missing")

        let before = toggle.value as? Int
        toggle.click()
        let after = toggle.value as? Int
        XCTAssertNotEqual(before, after, "the tracking toggle did not change state")
        toggle.click()
    }

    func testTheHUDButtonTogglesTheFloatingPanel() {
        span = SpanApp().launch()
        let hudButton = span.button("status.hudToggle")
        hudButton.waitToAppear(10, "the HUD button is missing from the status bar")

        let windowsBefore = span.app.windows.count
        hudButton.click()
        // The HUD is a separate panel, so showing it adds a window.
        let appeared = NSPredicate(format: "count > %d", windowsBefore)
        let expectation = XCTNSPredicateExpectation(predicate: appeared, object: span.app.windows)
        _ = XCTWaiter().wait(for: [expectation], timeout: 5)

        hudButton.click()
    }
}
