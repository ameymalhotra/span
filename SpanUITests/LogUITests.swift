import XCTest

/// The Log end to end: making a tab, writing to it, seeing the resume point
/// where you start work, and the handoff at the end of a session.
@MainActor
final class LogUITests: XCTestCase {

    private var span: SpanApp!

    override func setUp() { continueAfterFailure = false }
    override func tearDown() { span?.terminate(); span = nil }

    /// A multi-line `TextField` can surface as a text field or a text view
    /// depending on the macOS release.
    private func field(_ identifier: String) -> XCUIElement {
        let asField = span.app.textFields[identifier]
        return asField.exists ? asField : span.app.textViews[identifier]
    }

    private func element(_ identifier: String) -> XCUIElement {
        span.app.descendants(matching: .any)[identifier]
    }

    /// Opens the Log and creates a tab from the empty state.
    private func makeTab(_ name: String) {
        span.select("log")
        let nameField = span.textField("log.empty.name")
        nameField.waitToAppear(10, "the empty Log offered no way to make a tab")
        span.type(name, into: nameField)
        span.button("log.empty.create").click()
        element("log.tab.\(name)").waitToAppear(10, "the new tab is not in the sidebar")
    }

    private func writeEntry(resume: String) {
        let resumeField = field("log.resumePoint")
        span.type(resume, into: resumeField)
        span.button("log.save").click()
    }

    func testAnEntryWrittenInATabBecomesItsResumePoint() {
        span = SpanApp().launch()
        makeTab("Vector DB course")
        XCTAssertTrue(element("log.resumeCard.empty").waitForExistence(timeout: 10),
                      "a new tab should say nothing is logged yet")

        writeEntry(resume: "Continue the course")

        let card = span.app.staticTexts["log.resumeCard.text"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Pick up here did not show the entry")
        XCTAssertEqual(card.value as? String ?? card.label, "Continue the course")
        XCTAssertTrue(element("log.entry").waitForExistence(timeout: 10), "the entry is not in History")
    }

    func testTheLogSurvivesARelaunch() {
        span = SpanApp().launch()
        makeTab("Vector DB course")
        writeEntry(resume: "Read the cheat sheet")
        XCTAssertTrue(span.app.staticTexts["log.resumeCard.text"].waitForExistence(timeout: 10))

        span.relaunch()
        span.select("log")

        XCTAssertTrue(element("log.tab.Vector DB course").waitForExistence(timeout: 10),
                      "the tab was not saved")
        XCTAssertTrue(span.app.staticTexts["Read the cheat sheet"].waitForExistence(timeout: 10),
                      "the entry was not saved")
    }

    func testStartingFromATabShowsWhereYouLeftOff() {
        span = SpanApp().launch()
        makeTab("Vector DB course")
        writeEntry(resume: "Finish part 6")

        span.button("log.startSession").waitToAppear()
        span.button("log.startSession").click()

        XCTAssertTrue(span.textField("startSession.title").waitForExistence(timeout: 10),
                      "Start Session did not open the start sheet")
        XCTAssertTrue(span.app.staticTexts["Finish part 6"].waitForExistence(timeout: 10),
                      "the start sheet does not show the tab's resume point")
    }

    func testFinishingASessionForATabAsksWhereYouLeftOff() {
        span = SpanApp().launch()
        makeTab("Vector DB course")
        span.button("log.startSession").waitToAppear()
        span.button("log.startSession").click()
        span.button("startSession.start").waitToAppear()
        span.button("startSession.start").click()

        span.select("focus")
        span.button("focus.finish").waitToAppear()
        span.button("focus.finish").click()

        let resume = field("reflection.log.resumePoint")
        XCTAssertTrue(resume.waitForExistence(timeout: 10), "the review did not ask where you left off")
        span.type("Start at part 4", into: resume)
        // Skipping the ratings must still keep the handoff.
        span.button("reflection.skip").click()

        span.select("log")
        XCTAssertTrue(span.app.staticTexts["Start at part 4"].waitForExistence(timeout: 10),
                      "the handoff written at the end of the session was lost")
    }

    func testWithThePromptOffTheReviewIsUnchanged() {
        span = SpanApp(defaults: ["log.promptAtSessionEnd": "NO"]).launch()
        makeTab("Vector DB course")
        span.button("log.startSession").waitToAppear()
        span.button("log.startSession").click()
        span.button("startSession.start").waitToAppear()
        span.button("startSession.start").click()

        span.select("focus")
        span.button("focus.finish").waitToAppear()
        span.button("focus.finish").click()

        span.button("reflection.save").waitToAppear(10, "finishing did not offer a review")
        XCTAssertFalse(field("reflection.log.resumePoint").exists,
                       "the review asked for a log entry with the setting off")
    }
}
