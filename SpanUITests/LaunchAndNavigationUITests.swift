import XCTest

@MainActor
final class LaunchAndNavigationUITests: XCTestCase {

    private var span: SpanApp!

    override func setUp() { continueAfterFailure = false }
    override func tearDown() { span?.terminate(); span = nil }

    func testLaunchesToTheFocusPane() {
        span = SpanApp().launch()
        span.button("focus.start").waitToAppear(10, "the focus pane's start button is missing")
    }

    func testTheStoreIsRedirectedAwayFromTheRealDatabase() {
        span = SpanApp().launch()
        span.startSession(title: "Leaves a trace")

        // Something was written, and it was written into the test directory.
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: span.storeDirectory.path)) ?? []
        XCTAssertTrue(contents.contains { $0.hasPrefix("TimeManager.store") },
                      "the app did not write into the redirected store: \(contents)")
    }

    func testEverySidebarDestinationOpens() {
        span = SpanApp().launch()
        for destination in ["timeline", "day", "insights", "categories", "guide", "settings", "focus"] {
            span.select(destination)
            XCTAssertTrue(span.window.exists, "the window went away after selecting \(destination)")
        }
    }

    func testOnboardingAppearsOnFirstRunAndCanBeCompleted() {
        span = SpanApp(onboarded: false).launch()

        let name = span.textField("onboarding.userName")
        name.waitToAppear(10, "onboarding never appeared on a first run")
        span.type("Amey", into: name)

        let next = span.button("onboarding.continue")
        for _ in 0..<6 where next.exists && next.isEnabled {
            next.click()
        }

        name.waitToVanish(10)
        span.window.waitToAppear()
    }

    func testOnboardingBackStepsReturnToTheNameField() {
        span = SpanApp(onboarded: false).launch()

        let name = span.textField("onboarding.userName")
        name.waitToAppear()
        span.button("onboarding.continue").click()

        let back = span.button("onboarding.back")
        back.waitToAppear(10, "the Back button never appeared on the second step")
        back.click()
        XCTAssertTrue(name.waitForExistence(timeout: 5), "Back did not return to the name step")
    }

    func testOnboardingIsSkippedOnceCompleted() {
        span = SpanApp(onboarded: true).launch()
        XCTAssertFalse(span.textField("onboarding.userName").waitForExistence(timeout: 2),
                       "onboarding reappeared for a returning user")
    }
}
