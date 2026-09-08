# Testing

Two test targets, both in the `TimeManager` scheme.

- **`SpanTests`** — unit tests (Swift Testing). Fast, reliable, run these.
- **`SpanUITests`** — XCUITest driving the shipped app. See the caveat below.

## Running the unit tests

```sh
xcodebuild test -project TimeManager.xcodeproj -scheme TimeManager \
  -destination 'platform=macOS,arch=arm64' -only-testing:SpanTests \
  -derivedDataPath /tmp/TimeManagerBuild ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES
```

329 tests, about a second.

## Nothing touches your real data

`ModelStack.storeURL()` honours a `SPAN_STORE_DIRECTORY` environment
variable. The scheme's test action sets it, so a test run opens a store under
`/tmp` instead of `~/Library/Application Support/TimeManager`; unit tests that
need a real file build their own temporary store. `NotificationService` no-ops
under `SPAN_TESTING` so a run never schedules a real reminder or asks for
notification permission.

The test action also pins `TZ=America/Los_Angeles` and `en_US`, because the
formatters and the DST cases depend on both.

After a run, `~/Library/Application Support/TimeManager/TimeManager.store`
should be untouched and there should be no `Recovered-*.store` beside it.

## The UI tests need a stable code signature

They are written and they work — but only while macOS trusts the app for
automation, and it currently does not for long.

Span is unsandboxed and signed ad hoc (`CODE_SIGN_IDENTITY="-"`), so **every
rebuild produces a new code signature**. macOS keys the Accessibility grant to
that signature, which is the same reason the README says to sign rather than
pass `CODE_SIGNING_ALLOWED=NO`. Once the grant lapses, the runner fails every
test with:

```
Failed to load AX for com.ameymalhotra.timemanager: Not authorized for
performing UI testing actions.
```

The failures are fast and total — whole suites fall over in fractions of a
second — and they say nothing about the app.

To run them, sign with a stable identity (a Developer ID or a development
certificate) so the grant survives rebuilds, then authorise the app once under
System Settings → Privacy & Security → Accessibility:

```sh
xcodebuild test -project TimeManager.xcodeproj -scheme TimeManager \
  -destination 'platform=macOS,arch=arm64' -only-testing:SpanUITests \
  -derivedDataPath /tmp/TimeManagerBuild \
  CODE_SIGN_IDENTITY="Developer ID Application: …" DEVELOPMENT_TEAM=…
```

They also drive the real cursor and keyboard, so they need the machine to
themselves — anything that steals focus mid-test fails that test.

## What the UI tests cover

Onboarding and its five steps, every sidebar destination, the keyboard
shortcuts (⌘N ⌘B ⌘T ⌘[ ⌘]), day navigation and the date popover, the session
lifecycle through to the review sheet, block creation, renaming, deletion and
persistence across a relaunch, and the settings and category surfaces.

The menu bar panel and the HUD are not covered: both live outside the app's
main window and are impractical to address reliably from XCUITest.

## What is not tested

`ActivityTracker`'s sampling loop (`NSWorkspace` observers, `CGEventSource`
idle detection, `AXUIElement` window titles), `HUDController`'s window geometry
persistence, and `AccessibilityPermission` all talk straight to system APIs
with no injection point. Testing them would mean a dependency-injection
refactor rather than a test.
