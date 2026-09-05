import XCTest

/// Launches Span against a throwaway store and gives tests a vocabulary for
/// driving it.
///
/// Every launch points `SPAN_STORE_DIRECTORY` at a fresh temporary directory,
/// so nothing here can read or write the real database in
/// `~/Library/Application Support/TimeManager`.
@MainActor
struct SpanApp {

    let app: XCUIApplication
    let storeDirectory: URL

    static let timeout: TimeInterval = 10

    /// - Parameters:
    ///   - onboarded: false to get the first-run onboarding sheet.
    ///   - defaults: extra preferences, written through the argument domain.
    init(onboarded: Bool = true, defaults: [String: String] = [:]) {
        storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpanUITests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)

        app = XCUIApplication()
        app.launchEnvironment["SPAN_STORE_DIRECTORY"] = storeDirectory.path
        app.launchEnvironment["SPAN_TESTING"] = "1"
        app.launchEnvironment["TZ"] = "America/Los_Angeles"

        var preferences: [String: String] = [
            "hasOnboarded": onboarded ? "YES" : "NO",
            "hasSeenGuide": onboarded ? "YES" : "NO",
            // The HUD is a separate floating panel; keep it out of the way
            // unless a test asks for it.
            "hud.visible": "NO",
            "AppleLocale": "en_US",
        ]
        preferences.merge(defaults) { _, new in new }

        app.launchArguments = preferences.flatMap { ["-\($0.key)", $0.value] }
    }

    @discardableResult
    func launch() -> SpanApp {
        app.launch()
        XCTAssertTrue(window.waitForExistence(timeout: Self.timeout), "the main window never appeared")
        return self
    }

    /// Quits and reopens against the same store, so a test can check that
    /// something was actually written rather than just held in memory.
    func relaunch() {
        app.terminate()
        app.launch()
        XCTAssertTrue(window.waitForExistence(timeout: Self.timeout * 2),
                      "the window never came back after a relaunch")
        app.activate()
    }

    func terminate() {
        app.terminate()
        try? FileManager.default.removeItem(at: storeDirectory)
    }

    var window: XCUIElement { app.windows.firstMatch }

    // MARK: - Addressing controls

    func button(_ identifier: String) -> XCUIElement { app.buttons[identifier] }
    func textField(_ identifier: String) -> XCUIElement { app.textFields[identifier] }
    func checkBox(_ identifier: String) -> XCUIElement { app.checkBoxes[identifier] }

    /// Buttons live in different element classes depending on their style, so
    /// look wherever a clickable thing might be.
    func control(_ identifier: String) -> XCUIElement {
        for collection in [app.buttons, app.checkBoxes, app.popUpButtons,
                           app.menuButtons, app.radioButtons, app.staticTexts] {
            let element = collection[identifier]
            if element.exists { return element }
        }
        return app.descendants(matching: .any)[identifier]
    }

    /// SwiftUI does not carry an accessibility identifier onto the
    /// NSPopUpButton a `Picker` becomes, so menus are found by what they show.
    func popUpButton(showing value: String, timeout: TimeInterval = SpanApp.timeout) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for index in 0..<app.popUpButtons.count {
                let button = app.popUpButtons.element(boundBy: index)
                if (button.value as? String) == value { return button }
            }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        return nil
    }

    // MARK: - Navigation

    func select(_ destination: String, file: StaticString = #filePath, line: UInt = #line) {
        for attempt in 0..<3 {
            let row = app.descendants(matching: .any)["sidebar.\(destination)"]
            guard row.waitForExistence(timeout: Self.timeout) else {
                if attempt == 2 {
                    XCTFail("no sidebar row for \(destination)", file: file, line: line)
                }
                continue
            }
            app.activate()
            row.click()
            return
        }
    }

    func startSession(title: String, minutes: String? = nil) {
        let start = button("focus.start")
        if start.exists {
            start.click()
        } else {
            button("toolbar.startSession").click()
        }
        let field = textField("startSession.title")
        XCTAssertTrue(field.waitForExistence(timeout: Self.timeout), "the new-session sheet never opened")
        type(title, into: field)
        if let minutes {
            let segment = control("duration.\(minutes)")
            if segment.exists { segment.click() }
        }
        button("startSession.start").click()
    }

    /// Types into a field, making sure the app is frontmost and the field has
    /// keyboard focus first.
    ///
    /// `typeText` synthesises real key events, so it fails outright if anything
    /// steals focus mid-test — another app activating, a notification, the
    /// screen locking. Retrying around that keeps the suite usable on a machine
    /// someone is also working on.
    func type(_ text: String, into element: XCUIElement,
              file: StaticString = #filePath, line: UInt = #line) {
        element.waitToAppear(Self.timeout, "", file: file, line: line)
        for attempt in 0..<3 {
            app.activate()
            element.click()
            do {
                try element.typeTextSafely(text)
                return
            } catch {
                if attempt == 2 {
                    XCTFail("could not type into \(element): \(error)", file: file, line: line)
                }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }

    /// Presses a menu shortcut on the main window.
    func pressShortcut(_ key: String, modifiers: XCUIElement.KeyModifierFlags = .command) {
        app.typeKey(key, modifierFlags: modifiers)
    }
}

extension XCUIElement {
    @MainActor
    func waitToAppear(_ timeout: TimeInterval = SpanApp.timeout,
                      _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitForExistence(timeout: timeout),
                      message.isEmpty ? "\(self) never appeared" : message,
                      file: file, line: line)
    }

    @MainActor
    func waitToVanish(_ timeout: TimeInterval = SpanApp.timeout,
                      file: StaticString = #filePath, line: UInt = #line) {
        let gone = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: gone, object: self)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "\(self) never went away", file: file, line: line)
    }
}


extension XCUIElement {
    /// `typeText` traps rather than throwing when event synthesis times out, so
    /// the retry above needs a throwing wrapper around the check that predicts
    /// it: no keyboard focus means no events will land.
    @MainActor
    func typeTextSafely(_ text: String) throws {
        struct NoKeyboardFocus: Error {}
        guard (value(forKey: "hasKeyboardFocus") as? Bool) ?? true else { throw NoKeyboardFocus() }
        typeText(text)
    }
}
