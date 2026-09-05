# Time Manager

An iOS-first, local-only personal focus timer.

## Version 1

- Start a named timer with a category and 25, 50, 75, or 90-minute duration.
- Receive a local notification when the session ends.
- Pause, resume, extend, or finish a session.
- Record an honest review: focus rating, real-work minutes, distractions, and an optional note.
- Review today's completed sessions and totals.

Sessions are stored locally with SwiftData. No account, network connection, activity tracking, or health data is used in this version.

## Run it

Open `TimeManager.xcodeproj` in Xcode 26 or later, select an iPhone running iOS 17 or later, and run. Choose your Development Team and a unique bundle identifier before installing on a physical device.

## Verification

The project compiles with:

```sh
xcodebuild -project TimeManager.xcodeproj -scheme TimeManager \
  -destination 'generic/platform=iOS' -configuration Debug \
  -derivedDataPath /private/tmp/TimeManagerDeviceBuild build CODE_SIGNING_ALLOWED=NO
```
