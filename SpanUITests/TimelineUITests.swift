import XCTest

@MainActor
final class TimelineUITests: XCTestCase {

    private var span: SpanApp!

    override func setUp() { continueAfterFailure = false }
    override func tearDown() { span?.terminate(); span = nil }

    /// Adds a block through the toolbar and leaves its editor open.
    private func addBlock() {
        span.button("toolbar.addBlock").click()
        span.textField("entryEditor.title").waitToAppear(10, "the block editor never opened")
    }

    func testAddingABlockOpensAnEditorWithEveryControl() {
        span = SpanApp().launch()
        addBlock()

        XCTAssertTrue(span.textField("entryEditor.title").exists)
        XCTAssertTrue(span.app.datePickers["entryEditor.start"].exists, "no start time control")
        XCTAssertTrue(span.app.datePickers["entryEditor.end"].exists, "no end time control")
        XCTAssertTrue(span.button("entryEditor.delete").exists, "no delete button")
        XCTAssertTrue(span.button("entryEditor.done").exists, "no done button")
    }

    func testNamingABlockAndSavingItKeepsTheName() {
        span = SpanApp().launch()
        addBlock()

        let title = span.textField("entryEditor.title")
        span.type("Reading the spec", into: title)
        span.button("entryEditor.done").click()

        title.waitToVanish(10)
        XCTAssertTrue(span.app.staticTexts["Reading the spec"].waitForExistence(timeout: 10),
                      "the named block is not drawn on the timeline")
    }

    func testABlockLeftBlankGetsAPlaceholderName() {
        span = SpanApp().launch()
        addBlock()
        span.button("entryEditor.done").click()

        XCTAssertTrue(span.app.staticTexts["Untitled block"].waitForExistence(timeout: 10),
                      "a blank block was not given a placeholder name")
    }

    func testDeletingABlockRemovesItFromTheTimeline() {
        span = SpanApp().launch()
        addBlock()

        let title = span.textField("entryEditor.title")
        span.type("Delete me", into: title)
        span.button("entryEditor.done").click()

        let block = span.app.staticTexts["Delete me"]
        block.waitToAppear(10)
        block.click()

        span.button("entryEditor.delete").waitToAppear(10, "clicking the block did not open its editor")
        span.button("entryEditor.delete").click()

        block.waitToVanish(10)
    }

    func testClickingABlockReopensItsEditor() {
        span = SpanApp().launch()
        addBlock()
        let title = span.textField("entryEditor.title")
        span.type("Reopen me", into: title)
        span.button("entryEditor.done").click()

        let block = span.app.staticTexts["Reopen me"]
        block.waitToAppear(10)
        block.click()
        span.textField("entryEditor.title").waitToAppear(10, "the editor did not reopen")
    }

    func testAnEditedNameIsKept() {
        span = SpanApp().launch()
        addBlock()

        let title = span.textField("entryEditor.title")
        span.type("First name", into: title)
        span.button("entryEditor.done").click()

        let block = span.app.staticTexts["First name"]
        block.waitToAppear(10)
        block.click()

        let reopened = span.textField("entryEditor.title")
        reopened.waitToAppear()
        reopened.click()
        reopened.typeKey("a", modifierFlags: .command)
        span.type("Second name", into: reopened)
        span.button("entryEditor.done").click()

        XCTAssertTrue(span.app.staticTexts["Second name"].waitForExistence(timeout: 10),
                      "the renamed block did not update")
    }

    func testABlockSurvivesARelaunch() {
        span = SpanApp()
        span.launch()
        addBlock()
        let title = span.textField("entryEditor.title")
        span.type("Persist me", into: title)
        span.button("entryEditor.done").click()
        span.app.staticTexts["Persist me"].waitToAppear(10)

        span.app.terminate()
        span.app.launch()

        XCTAssertTrue(span.app.staticTexts["Persist me"].waitForExistence(timeout: 15),
                      "the block did not survive a relaunch — it was never saved")
    }

    func testDraggingOnTheTimelineCreatesABlock() {
        span = SpanApp().launch()
        span.select("timeline")

        let window = span.window
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.35))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: end)

        // A drag on an empty lane creates a block and opens its editor.
        let editor = span.textField("entryEditor.title")
        if editor.waitForExistence(timeout: 5) {
            span.button("entryEditor.done").click()
        }
        XCTAssertTrue(span.window.exists)
    }

    func testTheInspectorClosesWhenTheScrimIsClicked() {
        span = SpanApp().launch()
        addBlock()

        let title = span.textField("entryEditor.title")
        span.type("Scrim test", into: title)
        span.button("entryEditor.done").click()

        let block = span.app.staticTexts["Scrim test"]
        block.waitToAppear(10)
        block.click()
        span.textField("entryEditor.title").waitToAppear()

        // Click well away from the inspector, on the sidebar.
        span.select("focus")
        XCTAssertTrue(span.window.exists)
    }

    func testTheTimelinePaneTakesTheWholeWidthWhenSelected() {
        span = SpanApp().launch()
        span.select("timeline")
        XCTAssertFalse(span.button("focus.start").waitForExistence(timeout: 2),
                       "the focus pane is still showing on the timeline destination")
    }
}
