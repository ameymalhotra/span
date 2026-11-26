import XCTest

/// Exercises the notebook in the same isolated store as the existing Log UI
/// tests. Run only with the stable signing identity described in TESTING.md.
@MainActor
final class NotebookUITests: XCTestCase {
    private var span: SpanApp!
    override func setUp() { continueAfterFailure = false }
    override func tearDown() { span?.terminate(); span = nil }

    private func makeNotebook() {
        span = SpanApp().launch()
        span.select("log")
        span.type("Research", into: span.textField("log.empty.name"))
        span.button("log.empty.create").click()
        span.control("Notes").waitToAppear()
        span.control("Notes").click()
        span.button("notes.new").waitToAppear()
    }

    private func createNote(title: String, text: String) {
        span.button("notes.new").click()
        span.textField("notes.title").waitToAppear()
        span.type(title, into: span.textField("notes.title"))
        let editor = span.app.textViews["notes.body"]
        editor.waitToAppear()
        span.type(text, into: editor)
        span.app.typeKey("s", modifierFlags: .command)
        let status = span.app.staticTexts["notes.status"]
        let saved = NSPredicate(format: "label == 'Saved' OR value == 'Saved'")
        expectation(for: saved, evaluatedWith: status)
        waitForExpectations(timeout: 10)
    }

    func testNoteSurvivesNavigationAndRelaunch() {
        makeNotebook()
        createNote(title: "Paper ideas", text: "Compare retrieval methods")
        span.select("focus")
        span.select("log")
        XCTAssertEqual(span.textField("notes.title").value as? String, "Paper ideas")
        span.relaunch()
        span.select("log")
        span.textField("notes.title").waitToAppear()
        XCTAssertEqual(span.app.textViews["notes.body"].value as? String, "Compare retrieval methods")
    }

    func testSearchMatchesContentsAndKeepsTheEditorAvailable() {
        makeNotebook()
        createNote(title: "Paper ideas", text: "Vector databases")
        createNote(title: "Course", text: "Probability exercises")
        span.type("Vector", into: span.textField("notes.search"))
        XCTAssertTrue(span.app.staticTexts["Paper ideas"].waitForExistence(timeout: 10))
        XCTAssertFalse(span.app.staticTexts["Course"].exists)
    }

    func testRelatedNoteOpensInASeparateWindow() {
        makeNotebook()
        createNote(title: "Paper ideas", text: "Compare retrieval methods")
        span.control("Log").click()
        span.type("Read the methods section", into: span.textField("log.resumePoint"))
        span.control("Related notes").click()
        span.app.checkBoxes["Paper ideas"].click()
        span.button("log.save").click()
        span.app.links["Paper ideas"].waitToAppear()
        span.app.links["Paper ideas"].click()
        XCTAssertTrue(span.app.windows["Paper ideas"].waitForExistence(timeout: 10))
        XCTAssertEqual(span.app.windows.count, 2)
    }

    func testOpeningTheSameNoteFocusesItsExistingWindow() {
        makeNotebook()
        createNote(title: "Paper ideas", text: "A working note")
        span.button("notes.openWindow").click()
        XCTAssertTrue(span.app.windows["Paper ideas"].waitForExistence(timeout: 10))
        let main = span.app.windows.containing(.button, identifier: "notes.openWindow").firstMatch
        main.click()
        main.buttons["notes.openWindow"].click()
        XCTAssertEqual(span.app.windows.count, 2)
    }

    func testNotebookShortcutsDoNotStartSessionsOrCreateTimeBlocks() {
        makeNotebook()
        span.app.typeKey("n", modifierFlags: .command)
        span.textField("notes.title").waitToAppear()
        XCTAssertFalse(span.textField("startSession.title").exists)
        let editor = span.app.textViews["notes.body"]
        span.type("A bold idea", into: editor)
        span.app.typeKey("a", modifierFlags: .command)
        span.app.typeKey("b", modifierFlags: .command)
        XCTAssertTrue(editor.exists)
        XCTAssertFalse(span.textField("blockEditor.title").exists)
    }

}
