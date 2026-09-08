import SwiftData
import SwiftUI

/// The centre pane: the running session, or — when nothing is running — where
/// the day stands and the quickest ways back into work.
struct FocusPaneView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context

    @AppStorage("userName") private var userName = ""
    @AppStorage("personalNote") private var personalNote = ""
    @AppStorage("dailyFocusTargetMinutes") private var targetMinutes = 300
    @AppStorage("defaultSessionMinutes") private var defaultSessionMinutes = 60
    /// Titles cleared from the pick-up list, stamped with the day they were
    /// cleared. Dismissing is a "not today" rather than a permanent removal, so
    /// the list comes back tomorrow without the user having to undo anything.
    @AppStorage("pickUpDismissed") private var dismissedRaw = ""

    @Query private var todaySessions: [WorkSession]
    @Query private var recentSessions: [WorkSession]
    @Query private var todayEntries: [TimeEntry]

    let onStart: () -> Void
    let onFinish: () -> Void

    init(onStart: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.onStart = onStart
        self.onFinish = onFinish

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: .now)
        _todaySessions = Query(filter: #Predicate<WorkSession> { $0.startedAt >= dayStart },
                               sort: \.startedAt)
        // A fortnight is enough to surface what you actually keep returning to
        // without dredging up a one-off from last month.
        let recentStart = calendar.date(byAdding: .day, value: -14, to: dayStart) ?? dayStart
        _recentSessions = Query(filter: #Predicate<WorkSession> { $0.startedAt >= recentStart },
                                sort: \.startedAt, order: .reverse)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        _todayEntries = Query(filter: #Predicate<TimeEntry> { $0.startedAt >= dayStart && $0.startedAt < dayEnd },
                              sort: \.startedAt)
    }

    /// The day's total comes from the model, which counts sessions and
    /// hand-made blocks alike — the same number the status bar and the HUD
    /// show, rather than a second opinion computed here.
    private var focusToday: TimeInterval { model.focusToday }

    private var targetFraction: Double {
        let target = TimeInterval(max(1, targetMinutes) * 60)
        return min(1, focusToday / target)
    }

    /// Distinct recent pieces of work, most recent first, minus anything
    /// dismissed today.
    private var pickUpAgain: [WorkSession] {
        let hidden = dismissedToday
        var seen: Set<String> = []
        var result: [WorkSession] = []
        for session in recentSessions where session.status == .completed {
            let key = session.title.trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty, !seen.contains(key), !hidden.contains(key) else { continue }
            seen.insert(key)
            result.append(session)
            if result.count == 3 { break }
        }
        return result
    }

    private static let dayStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Stored as "yyyy-MM-dd\ntitle\ntitle". A stamp from any other day is
    /// treated as empty, which is what makes the list reset overnight without
    /// anything having to run at midnight.
    private var dismissedToday: Set<String> {
        let parts = dismissedRaw.components(separatedBy: "\n")
        guard let stamp = parts.first,
              stamp == Self.dayStamp.string(from: .now) else { return [] }
        return Set(parts.dropFirst())
    }

    private func dismiss(_ session: WorkSession) {
        let key = session.title.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return }
        var titles = dismissedToday
        titles.insert(key)
        dismissedRaw = ([Self.dayStamp.string(from: .now)] + titles.sorted())
            .joined(separator: "\n")
    }

    /// A hand-made block covering the present moment. Drawing one across now is
    /// a statement about what you are doing, so the pane should say so rather
    /// than greeting you as though nothing were happening.
    private func blockHappeningNow(at now: Date) -> TimeEntry? {
        todayEntries.first { $0.startedAt <= now && now < $0.endedAt }
    }

    var body: some View {
        ZStack {
            Theme.canvas
            if model.isOnBreak {
                onBreak
            } else if let session = model.activeSession {
                running(session)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let block = blockHappeningNow(at: context.date) {
                        happeningNow(block, at: context.date)
                    } else {
                        idle
                    }
                }
            }
        }
        // The one-second clock only runs while this pane is on screen.
        .onAppear { model.beginFastUpdates() }
        .onDisappear { model.endFastUpdates() }
    }

    // MARK: - Nothing running

    private var idle: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(Format.greeting(userName))
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.label)
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.secondaryLabel)
            }

            todayRing

            Button(action: onStart) {
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: "play.fill").font(.system(size: 11))
                    Text("Start a session")
                    Text("·")
                        .foregroundStyle(Theme.onAccent.opacity(0.6))
                    Text(Format.compact(TimeInterval(defaultSessionMinutes * 60)))
                        .monospacedDigit()
                        .foregroundStyle(Theme.onAccent.opacity(0.75))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .foregroundStyle(Theme.onAccent)
            .controlSize(.large)
            .keyboardShortcut("n", modifiers: .command)

            HStack(spacing: Theme.Space.m) {
                Text("Take a break")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                BreakOptions { model.startBreak(minutes: $0) }
                Spacer(minLength: 0)
            }

            if !pickUpAgain.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack(spacing: Theme.Space.xs) {
                        Text("Pick up again")
                            .font(Theme.Font.sectionHeader)
                            .tracking(0.5)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.tertiaryLabel)
                        Spacer()
                        if !dismissedToday.isEmpty {
                            Button("Reset") { dismissedRaw = "" }
                                .buttonStyle(.link)
                                .font(Theme.Font.micro)
                        }
                    }
                    ForEach(pickUpAgain) { session in
                        resumeRow(session)
                    }
                }
            }

            if !personalNote.isEmpty {
                Text(personalNote)
                    .font(Theme.Font.body)
                    .italic()
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 360)
        .padding(Theme.Space.xxl)
    }

    /// Today against the target — the same ring the countdown uses, so progress
    /// reads the same way whether or not a session is running.
    private var todayRing: some View {
        HStack(spacing: Theme.Space.xl) {
            ProgressRing(progress: targetFraction, colour: Theme.accent, diameter: 132, width: 8) {
                VStack(spacing: 1) {
                    Text(Format.compact(focusToday))
                        .font(.system(size: 22, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.label)
                    Text("focused")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.tertiaryLabel)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                statLine(Format.percent(targetFraction), "of your \(Format.compact(TimeInterval(targetMinutes * 60))) target")
                statLine("\(todaySessions.filter { $0.status == .completed }.count)",
                         "sessions finished today")
                if focusToday > 0 {
                    statLine(Format.compact(max(0, TimeInterval(targetMinutes * 60) - focusToday)),
                             "left to reach it")
                }
            }
        }
    }

    private func statLine(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
            Text(value)
                .font(Theme.Font.body.weight(.medium).monospacedDigit())
                .foregroundStyle(Theme.label)
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }

    /// One tap starts the same work again; the cross clears it for today.
    private func resumeRow(_ session: WorkSession) -> some View {
        HStack(spacing: Theme.Space.s) {
            Button {
                model.startSession(title: session.title,
                                   category: session.category,
                                   minutes: defaultSessionMinutes)
            } label: {
                HStack(spacing: Theme.Space.s) {
                    Circle()
                        .fill(CategoryPalette.color(for: session.category))
                        .frame(width: 8, height: 8)
                    Text(session.title)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.label)
                        .lineLimit(1)
                    Spacer(minLength: Theme.Space.s)
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.tertiaryLabel)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Start this again for \(Format.compact(TimeInterval(defaultSessionMinutes * 60)))")

            Button {
                dismiss(session)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryLabel)
            }
            .buttonStyle(.plain)
            .help("Not today — back tomorrow")
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    // MARK: - A block covering now

    /// The same treatment a running session gets, because from the user's side
    /// this is a running thing — it simply has no timer attached yet.
    private func happeningNow(_ block: TimeEntry, at now: Date) -> some View {
        let elapsed = now.timeIntervalSince(block.startedAt)
        let remaining = max(0, block.endedAt.timeIntervalSince(now))
        let progress = block.duration > 0 ? min(1, elapsed / block.duration) : 0
        let colour = CategoryPalette.color(for: block.category)

        return VStack(spacing: Theme.Space.xl) {
            VStack(spacing: Theme.Space.xs) {
                Text("HAPPENING NOW")
                    .font(Theme.Font.sectionHeader)
                    .tracking(0.8)
                    .foregroundStyle(colour)
                Text(block.title.isEmpty ? "Untitled block" : block.title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(block.title.isEmpty ? Theme.tertiaryLabel : Theme.label)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            ProgressRing(progress: progress, colour: colour, diameter: 248, width: 7) {
                VStack(spacing: Theme.Space.xs) {
                    Text(Format.clock(remaining))
                        .font(Theme.Font.timer)
                        .foregroundStyle(Theme.label)
                    Text("left of \(Format.compact(block.duration))")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }

            VStack(spacing: Theme.Space.s) {
                Button {
                    model.startSession(from: block)
                } label: {
                    Label("Start tracking this", systemImage: "play.fill")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .foregroundStyle(Theme.onAccent)
                .controlSize(.large)

                Text("A block is a plan until you start it. Starting counts the time since \(Format.timeOfDay(block.startedAt)).")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.tertiaryLabel)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("\(Format.compact(focusToday)) focused today · \(Format.percent(targetFraction)) of target")
                .font(Theme.Font.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.tertiaryLabel)
        }
        .padding(Theme.Space.xxl)
    }

    // MARK: - Running

    private func running(_ session: WorkSession) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = session.elapsed(at: context.date)
            let remaining = session.remaining(at: context.date)
            let progress = min(1, elapsed / max(1, session.plannedDuration))
            let colour = CategoryPalette.color(for: session.category)

            VStack(spacing: Theme.Space.xl) {
                VStack(spacing: Theme.Space.xs) {
                    Text(session.category.uppercased())
                        .font(Theme.Font.sectionHeader)
                        .tracking(0.8)
                        .foregroundStyle(colour)
                    Text(session.title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.label)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                ProgressRing(progress: progress, colour: colour, diameter: 248, width: 7) {
                    VStack(spacing: Theme.Space.xs) {
                        Text(Format.clock(remaining))
                            .font(Theme.Font.timer)
                            .foregroundStyle(Theme.label)
                        Text(statusLine(session, remaining: remaining))
                            .font(Theme.Font.caption)
                            .foregroundStyle(remaining <= 0 ? .orange : Theme.secondaryLabel)
                    }
                }

                controls(session)

                Text("\(Format.compact(focusToday)) focused today · \(Format.percent(targetFraction)) of target")
                    .font(Theme.Font.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.tertiaryLabel)
            }
            .padding(Theme.Space.xxl)
        }
    }

    private func statusLine(_ session: WorkSession, remaining: TimeInterval) -> String {
        if session.status == .paused { return "Paused" }
        if remaining <= 0 { return "Time's up — finish when you're ready" }
        return "of \(Format.compact(session.plannedDuration))"
    }

    private func controls(_ session: WorkSession) -> some View {
        VStack(spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.m) {
                if session.status == .paused {
                    Button("Resume") { model.resumeSession() }
                        .buttonStyle(.bordered)
                } else {
                    Button("Pause") { model.pauseSession() }
                        .buttonStyle(.bordered)
                }
                Button("Finish", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.onAccent)
            }
            .controlSize(.large)

            if session.remaining() <= 0 {
                Button("Add 5 minutes") { model.extendSession(byMinutes: 5) }
                    .buttonStyle(.link)
                    .font(Theme.Font.caption)
            }

            // Starting a break here pauses the session, which is the whole
            // reason to offer it from inside one: a break counted as work is
            // the arithmetic this app exists to avoid.
            HStack(spacing: Theme.Space.s) {
                Text("Break")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.tertiaryLabel)
                BreakOptions { model.startBreak(minutes: $0) }
            }
        }
    }

    // MARK: - On a break

    private var onBreak: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = model.breakRemaining(at: context.date)
            let length = max(1, model.breakLength)
            let progress = min(1, max(0, (length - remaining) / length))

            VStack(spacing: Theme.Space.xl) {
                VStack(spacing: Theme.Space.xs) {
                    Text("ON A BREAK")
                        .font(Theme.Font.sectionHeader)
                        .tracking(0.8)
                        .foregroundStyle(Theme.rest)
                    Text(model.breakEndsAt.map { "Back at \(Format.timeOfDay($0))" } ?? "")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.label)
                }

                ProgressRing(progress: progress, colour: Theme.rest, diameter: 248, width: 7) {
                    VStack(spacing: Theme.Space.xs) {
                        Text(Format.clock(remaining))
                            .font(Theme.Font.timer)
                            .foregroundStyle(Theme.label)
                        Text("left of \(Format.compact(length))")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }

                VStack(spacing: Theme.Space.m) {
                    HStack(spacing: Theme.Space.m) {
                        Button("Add 5 minutes") { model.extendBreak(byMinutes: 5) }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("break.extend")
                        Button(model.sessionPausedForBreak ? "Back to work" : "End break") {
                            model.endBreak()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.rest)
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("break.end")
                    }
                    .controlSize(.large)

                    if model.sessionPausedForBreak {
                        Text("Your session is paused. Coming back starts it again.")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.tertiaryLabel)
                    }
                }

                Text("\(Format.compact(focusToday)) focused today · \(Format.percent(targetFraction)) of target")
                    .font(Theme.Font.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.tertiaryLabel)
            }
            .padding(Theme.Space.xxl)
        }
    }
}

/// A ring with a label in the middle. Used for both the countdown and the day's
/// progress, so the two read as the same measure.
struct ProgressRing<Label: View>: View {
    let progress: Double
    let colour: Color
    let diameter: CGFloat
    let width: CGFloat
    @ViewBuilder let label: () -> Label

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.hairline, lineWidth: width)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(colour, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)
            label()
        }
        .frame(width: diameter, height: diameter)
    }
}
