import SwiftUI

/// What the app does, how it does it, and how to tune it.
///
/// Written to be read once and returned to occasionally, so it explains the
/// mechanism rather than only listing controls — particularly for tracking,
/// where knowing what is and is not recorded is the difference between trusting
/// the app and turning it off.
struct GuideView: View {

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Guide", subtitle: "How Span works")
            Divider()
            ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                intro
                sessions
                timeline
                blocks
                tracking
                categories
                review
                surfaces
                tuning
                personal
                shortcuts
                privacy
            }
            .padding(.horizontal, Theme.Space.page)
            .padding(.top, Theme.Space.page)
            .padding(.bottom, Theme.Space.page)
            .frame(maxWidth: 720, alignment: .leading)
            }
        }
        .background(Theme.canvas)
    }

    // MARK: - Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Where the day went")
                .font(.system(size: 24, weight: .semibold))
            Text("""
            Span answers one question: where did the day actually go? It \
            does that by putting three different kinds of time on a single \
            timeline — the sessions you start deliberately, the blocks you \
            write down yourself, and what your Mac was doing while you worked.
            """)
            .foregroundStyle(Theme.secondaryLabel)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sessions: some View {
        card("Focus sessions", "The time you set out to spend on something.") {
            para("Start one from the Focus pane or the toolbar. Give it a name, a category and a length — 30 minutes, an hour, 90 minutes, two hours, or anything you type in. The ring counts down and the menu bar shows the same number.")
            para("Pausing a session stops the clock. That matters for the arithmetic: a session records each stretch you actually worked, so a 60-minute session paused for 15 counts as 45 minutes of focus, not 60. Those stretches are also what the timeline draws, which is why a session you broke off appears as two blocks with a gap.")
            note("Pauses shorter than ten minutes are drawn as one block. Below that, a gap is noise rather than a break.")
            para("Breaks have a timer of their own. Five, ten or fifteen minutes from the Focus pane, or any length you type, and Span sounds the end of it the way it sounds the end of a session. Starting a break pauses whatever session is running — a break counted as work would defeat the point — and coming back starts it again. Finish a session and you are asked whether you want one.")
            para("You do not have to remember to press Finish. Walk away for longer than the grace period in Settings — half an hour to begin with — and the session is finished where you stopped, not where you came back, so one left running overnight ends at last night's last keystroke rather than banking sixteen hours. Set it to Never if you would rather close every session yourself.")
        }
    }

    private var timeline: some View {
        card("Reading the timeline", "Two tracks, on purpose.") {
            bullet("The narrow rail on the left is what your Mac was doing — one continuous band, coloured by category. It never overlaps, because only one app is ever in front.")
            bullet("The wide lane holds sessions and the blocks you add yourself. These can overlap, and when they do they split into columns the way calendar events do.")
            bullet("The red line is now. It only appears on today.")
            GuideDiagram.timeline
            para("Hover anywhere on the rail to see what that stretch was, including the document or page when window titles are available. The legend along the top names the colours with their totals, so you rarely need to hover at all. Click any block in the wide lane to open it beside itself.")
            note("Short blocks are drawn slightly taller than their true length so they stay readable and clickable. In a busy stretch that nudges blocks apart by a minute or two — the same trade calendars make. Zoom in from the toolbar to see true proportions.")
        }
    }

    private var blocks: some View {
        card("Adding time by hand", "For work that happened away from the Mac, or that tracking got wrong.") {
            bullet("Drag anywhere on the timeline's wide lane to sweep out a block. It snaps to five minutes, and opens for naming as soon as you let go.")
            bullet("Drag a block's middle to move it. Hover near its top or bottom edge and a grip appears — drag that to change when it started or ended.")
            bullet("Open a block to set exact start and end times, so you are never stuck with wherever the drag landed.")
            bullet("Finished sessions resize the same way. If you kept working past the end of one, pull its bottom edge down rather than logging a second block.")
            bullet("⌘B adds a block at the current time without dragging.")
            bullet("A block counts towards the day's focus and your daily target, the same as a session — it is time you are vouching for. Only the part that has already happened counts, so a block drawn across the afternoon fills in as the afternoon passes.")
            note("A block is a plan, not a running clock. Draw one across the present and the Focus pane shows it counting down, with a button to start tracking it — which counts the time already inside the block and runs to its end.")
            GuideDiagram.dragToCreate
        }
    }

    private var tracking: some View {
        card("What automatic tracking records", "Plainly, because this is the part worth understanding.") {
            para("Every few seconds the app asks macOS two things: which application is in front, and how long it has been since you last touched the keyboard or trackpad. That is the whole mechanism.")
            bullet("It records a span per app — “Safari, 9:12 to 9:34” — and nothing about what you typed.")
            bullet("Asking when you last touched the keyboard tells it *when* input happened, never *what* the input was. It cannot see keystrokes.")
            bullet("Go quiet for longer than your away threshold and the app records a break, back-dated to when input actually stopped rather than when it noticed.")
            bullet("Flicking between apps is absorbed: anything under ten seconds folds into the surrounding stretch instead of littering the day.")
            bullet("Sleeping the Mac or locking the screen is recorded as away, so waking up hours later does not read as an all-night stretch in whatever was open.")
            para("Granting Accessibility in Settings adds one thing: the title of the focused window, which is where a browser's page title comes from. Without it you still get every app and every break — blocks just say “Safari” instead of “Safari — the page you were on”.")
            note("Nothing is recorded while tracking is paused, and a gap in the recording counts as a break rather than as unbroken work.")
        }
    }

    private var categories: some View {
        card("Categories", "Your names, your colours.") {
            para("A category is just a name with a colour. Seven come set up; add your own — school work, admin, whatever you actually do — from the picker in a session or block, or in Settings.")
            para("The activity rail can group your apps two ways, switchable from the legend above the timeline or in Settings. By category, Safari and Chrome both read as Browsing; by app, they are listed separately. Either way you can tell Span which category any app belongs to, and it re-files the time already recorded rather than only what comes next.")
            para("Ten preset colours are chosen to stay apart from one another, including for the most common kinds of colour blindness. If none of them suit, the colour wheel takes anything you like.")
            note("Past ten categories some colours become hard to tell apart. That is why every list shows the category's name next to its colour rather than relying on colour alone.")
        }
    }

    private var review: some View {
        card("The honest review", "The bit that makes the numbers mean something.") {
            para("When a session ends you can rate your focus, say how much of the time was genuinely work, and note what pulled you away. This is optional, and skipping is recorded as skipping rather than as a zero.")
            para("The Day and Insights panes then show two separate numbers: time on the clock, and time that felt real. The gap between them is the point of the exercise — a timer alone will happily tell you that you worked eight hours.")
        }
    }

    private var surfaces: some View {
        card("Menu bar and the floating HUD", "For when the window is not in front.") {
            bullet("The menu bar shows the running session's remaining time, and its panel can start, pause and finish one.")
            bullet("The HUD is the small capsule below the menu bar: time since your last break, focus today, and how close you are to your target. Clicking it never takes focus away from whatever you are working in.")
            bullet("Drag the HUD anywhere along the top of the screen; it remembers where you put it. Hide it from Settings, the status bar, or its own menu.")
            GuideDiagram.hud
        }
    }

    private var tuning: some View {
        card("Tuning it to you", "What each setting actually changes.") {
            setting("Daily target",
                    "Sets the denominator for “percent of target” in the status bar and the HUD, and the streak in Insights. Pick something you would actually hit on a normal day — a target you miss daily stops meaning anything.")
            setting("Default session",
                    "The length pre-selected when you start a session. Set it to whatever you reach for most.")
            setting("Away after",
                    "How long without input counts as a break. Shorter means breaks are caught accurately, but reading a long document counts as away. Longer means fewer false breaks, but a coffee run gets billed as work. Five minutes suits most people; two if you want the break counter to be strict.")
            setting("Window titles",
                    "Turns app-level tracking into document-level tracking. Worth it if you want to know which project you were in; skip it if window titles in your work are sensitive.")
            setting("Sound when time is up",
                    "A chime and a Dock bounce the moment a session's planned time runs out. On by default, and it needs no permission from macOS.")
            setting("Session end notification",
                    "A banner as well, so the end reaches you with the window closed. This one macOS has to allow; Span asks the first time you start a session.")
        }
    }

    private var personal: some View {
        card("Making it yours", nil) {
            para("Span asks for your name when you first run it, and greets you with it on the Focus pane. It is stored on this Mac and never sent anywhere.")
            para("You can also set a line of your own — a reason, a reminder, something you are working towards. It appears on the Focus pane and again when you start a session, which is the moment it is most likely to matter. Both are editable in Settings, and both can be left empty.")
        }
    }

    private var shortcuts: some View {
        card("Keyboard", nil) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                shortcut("⌘N", "Start a session")
                shortcut("⌘B", "Add a time block at now")
                shortcut("⌘T", "Jump to today")
                shortcut("⌘[  ⌘]", "Previous or next day")
                shortcut("⌘,", "Settings")
            }
        }
    }

    private var privacy: some View {
        card("Where your data lives", nil) {
            para("Everything stays in a single file on this Mac, under Application Support. There is no account and no sync; nothing you record is ever uploaded.")
            para("Span makes exactly one network request: once a day it asks GitHub whether a newer version has been released. It sends nothing but the request, and you can switch it off in Settings.")
            para("When there is one, Settings will download and install it for you — Span closes, swaps itself for the new copy and reopens. You never have to visit a web page or drag anything over the version you are running.")
            para("Settings also has the way out — delete the tracked activity on its own, or reset Span entirely and start over.")
        }
    }

    // MARK: - Chrome

    private func card(_ title: String, _ subtitle: String?,
                      @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.tertiaryLabel)
                }
            }
            content()
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func para(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.body)
            .foregroundStyle(Theme.secondaryLabel)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            Circle()
                .fill(Theme.tertiaryLabel)
                .frame(width: 4, height: 4)
                .padding(.top, 7)
            Text(text)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func note(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent)
                .padding(.top, 1)
            Text(text)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.tertiaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentMuted, in: RoundedRectangle(cornerRadius: 6))
    }

    private func setting(_ name: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(Theme.Font.body.weight(.medium))
                .foregroundStyle(Theme.label)
            Text(text)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func shortcut(_ keys: String, _ label: String) -> some View {
        HStack(spacing: Theme.Space.m) {
            Text(keys)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.label)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.hairline, lineWidth: 0.5))
                .frame(width: 84, alignment: .leading)
            Text(label)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }
}
