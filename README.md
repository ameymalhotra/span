# Span

A macOS time tracker named for what it records: a span of time. Built around a single question: where did the day actually go?

The main window is three panes — a focus timer, a day timeline, and review
surfaces — plus a menu bar item and a floating HUD that stays readable while you
work in other apps.

## What it records

Three sources, drawn on one timeline:

- **Focus sessions** you start by hand, with a planned duration and a category.
- **Time entries** you write yourself, for work that happened away from the Mac.
- **Tracked activity** — which app was frontmost, and when you stepped away.

Sessions record each *run* as its own interval, so a session you paused for ten
minutes draws as two blocks with a real gap, and its duration excludes the break.

## The honest review

When a session ends you can rate your focus, say how much of the time was real
work, and note what pulled you away. The day summary reports wall-clock time and
honest work as two separate numbers — the gap between them is the point. Sessions
you have not reviewed are shown as unreviewed rather than counted as zero.

## Tracking and privacy

Recording the frontmost app and your idle time needs no permission at all.
Granting Accessibility additionally lets a timeline block show the document or
page that was open; tracking works without it, and the app never blocks on it.

Everything stays in `~/Library/Application Support/TimeManager`. There is no
account, no sync, and nothing leaves the machine.

Because reading window titles requires Accessibility, the app is intentionally
**not** sandboxed and so cannot ship on the Mac App Store; distribute it with
Developer ID signing and notarization.

## Requirements

macOS 14 or later. Xcode 16 or later.

## Build and run

```sh
xcodebuild -project TimeManager.xcodeproj -scheme TimeManager \
  -destination 'platform=macOS,arch=arm64' -configuration Debug \
  -derivedDataPath /tmp/TimeManagerBuild \
  build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES

open /tmp/TimeManagerBuild/Build/Products/Debug/Span.app
```

Sign the build rather than passing `CODE_SIGNING_ALLOWED=NO`: macOS keys the
Accessibility grant to the code signature, so an unsigned binary has to be
re-authorised on every rebuild. Use `CODE_SIGNING_ALLOWED=NO` only for a
compile-only check.

To start from an empty database, delete `~/Library/Application Support/TimeManager`.
