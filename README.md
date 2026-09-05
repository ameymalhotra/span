# Span

A macOS time tracker that answers one question: **where did the day actually go?**

Span puts three different kinds of time on a single day timeline — the focus
sessions you start deliberately, the blocks you write down yourself, and what
your Mac was doing while you worked — and then asks you how much of it was
genuinely work.

Everything you record stays on your machine. There is no account and no sync.
Span makes one network request — a daily check for a new version — which you
can switch off.

---

## Install

**[Download the latest DMG →](../../releases/latest)**

1. Open `Span-1.0.dmg` and drag **Span** into **Applications**.
2. Open **Terminal** and run:

   ```sh
   xattr -dr com.apple.quarantine /Applications/Span.app
   ```

3. Launch Span from Applications.

### Why step 2 is necessary

Span is not signed with an Apple Developer ID, so macOS quarantines it on
download and refuses to open it — usually with *"Span is damaged and can't be
opened."* The app is not damaged; that is simply what macOS says about an
unsigned app that came from the internet. The command above removes the
quarantine flag that the download added.

Right-clicking and choosing **Open** is *not* enough for an ad-hoc-signed app
on recent macOS. The Terminal command is the reliable route.

The honest fix is a paid Apple Developer account, a Developer ID signature and
notarization. Until then, this step is the cost of installing it.

**Requires macOS 14 (Sonoma) or later.** Apple Silicon.

---

## What it does

### Focus sessions

Start a session with a name, a category and a length — 30 minutes, an hour, 90
minutes, two hours, or anything you type in. The ring counts down and the menu
bar shows the same number.

Pausing stops the clock, and that matters for the arithmetic: a session records
each stretch you actually worked, so a 60-minute session paused for 15 counts
as 45 minutes of focus. Those stretches are also what the timeline draws, which
is why a session you broke off appears as two blocks with a gap between them.

### The honest review

When a session ends you can rate your focus, say how much of the time was
genuinely work, and note what pulled you away. Skipping is recorded as skipping
rather than as a zero.

The day and week views then show two separate numbers — time on the clock, and
time that felt real. **The gap between them is the point.** A timer alone will
happily tell you that you worked eight hours.

### The timeline

Two tracks, deliberately:

- A narrow **rail** on the left is what your Mac was doing — one continuous
  band, coloured by category. Hover it to see any stretch; a legend above names
  the colours with their totals.
- A wide **lane** holds sessions and the blocks you add by hand. These can
  overlap, and when they do they split into columns the way calendar events do.

Drag empty space to sweep out a block; it snaps to five minutes and opens for
naming. Drag a block to move it, or its top or bottom edge to change when it
started or ended — finished *and* running sessions both.

### Automatic tracking

Every few seconds Span asks macOS two things: which application is in front,
and how long since you last touched the keyboard or trackpad. That is the whole
mechanism.

- It records a span per app — *"Safari, 9:12 to 9:34"* — and nothing about what
  you typed. Asking *when* input last happened is not the same as seeing *what*
  it was, and Span cannot read keystrokes or screen contents.
- Go quiet for longer than your away threshold and it records a break,
  back-dated to when input actually stopped rather than when it noticed.
- Short switches are absorbed, so alt-tabbing does not litter the day.
- Sleeping or locking the Mac is recorded as away, so waking hours later does
  not read as an all-night stretch in whatever was open.

Granting **Accessibility** (Settings → Tracking) adds one thing: the title of
the focused window, which is where a browser's page title comes from. Without
it you still get every app and every break — blocks just say "Safari" rather
than "Safari — the page you were on". Tracking never blocks on it.

### Categories

A category is a name with a colour. Seven come set up; add your own from the
picker or in Settings. Ten preset colours are chosen to stay apart from one
another, including for the most common kinds of colour blindness, and a colour
wheel is there when none of them suit.

You decide which category each app belongs to, and changing that re-files the
time already recorded rather than only what comes next. The rail can group by
category (Safari and Chrome both read as *Browsing*) or by app (listed
separately) — switchable from the legend.

### Elsewhere

- **Insights** — a 14-day trend against your target, on-the-clock against time
  that felt real, and where the hours went.
- **Menu bar** — the running session's remaining time; start, pause and finish
  from its panel.
- **Floating HUD** — a small capsule below the menu bar showing time since your
  last break, focus today, and progress toward your target. Clicking it never
  takes focus from the app you are working in.
- **Guide** — an in-app explanation of all of the above, opened on first run.

---

## Keyboard

| | |
|---|---|
| `⌘N` | Start a session |
| `⌘B` | Add a time block at the current time |
| `⌘T` | Jump to today |
| `⌘[` `⌘]` | Previous / next day |
| `⌘,` | Settings |

---

## Your data

One file, on your Mac:

```
~/Library/Application Support/Span/Span.store
```

Nothing you record is ever uploaded. **Settings → Your data** can delete the
tracked activity on its own, or reset Span entirely — erasing every session,
block, category and preference and starting the setup questions again. Deleting
the folder above does the same thing by hand.

The one thing Span sends anywhere is a daily check against the GitHub releases
API to see whether a newer version exists. It transmits nothing but the request,
and **Settings → Updates** turns it off.

Because window-title capture needs Accessibility, Span is deliberately **not**
sandboxed, and so cannot ship on the Mac App Store.

---

## Build from source

Requires Xcode 16 or later.

```sh
git clone https://github.com/ameymalhotra/span.git
cd span
xcodebuild -project TimeManager.xcodeproj -scheme TimeManager \
  -destination 'platform=macOS,arch=arm64' -configuration Debug \
  -derivedDataPath /tmp/SpanBuild \
  build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES

open /tmp/SpanBuild/Build/Products/Debug/Span.app
```

Sign the build rather than passing `CODE_SIGNING_ALLOWED=NO`: macOS keys the
Accessibility grant to the code signature, so an unsigned binary has to be
re-authorised on every rebuild. Use `CODE_SIGNING_ALLOWED=NO` only for a
compile-only check.

### Tests

262 unit tests, about a second. See [TESTING.md](TESTING.md).

```sh
xcodebuild test -project TimeManager.xcodeproj -scheme TimeManager \
  -destination 'platform=macOS,arch=arm64' -only-testing:SpanTests \
  -derivedDataPath /tmp/SpanBuild ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES
```

Tests never touch your real data — the scheme points the store at `/tmp` and
stubs out notifications.

---

## Layout

```
TimeManager/
├── App/          Scenes, the shared model, the SwiftData stack
├── Models/       WorkSession, SessionSegment, ActivityRecord, TimeEntry,
│                 TimeCategory, AppCategoryRule
├── Tracking/     Frontmost-app tracking, idle detection, categorisation
├── Timeline/     Geometry, layout, blocks, the day view and its editors
├── Views/        Panes, shell, onboarding, shared controls
├── HUD/          The floating capsule
└── Design/       Theme, palette, formatters
```

---

## Known limitations

- **Not notarized.** See the install note above.
- **Apple Silicon only** as built. The source has no architecture-specific
  code, so an Intel or universal build is a matter of changing the destination.
- **Ten category colours.** Beyond ten, some categories share one. Every list
  shows the category name beside its colour for that reason.
- **Two windows editing at once is untested.** It is a single-user local app.

---

## Roadmap

- A weekly review that makes the reflection data earn its keep
- Attributing idle time — saying what a break actually was
- Export to CSV and JSON
- Rules finer than the app name (a URL, not just "Safari")

---

No licence is declared, so all rights are reserved by default. Add a `LICENSE`
file if you want others to be able to use or modify this.
