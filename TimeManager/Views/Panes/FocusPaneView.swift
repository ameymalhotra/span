import SwiftUI

/// The centre pane: one large ring showing the running session, or an invitation
/// to start one.
struct FocusPaneView: View {
    @Environment(AppModel.self) private var model

    @AppStorage("userName") private var userName = ""
    @AppStorage("personalNote") private var personalNote = ""

    let onStart: () -> Void
    let onFinish: () -> Void

    var body: some View {
        ZStack {
            Theme.canvas
            if let session = model.activeSession {
                running(session)
            } else {
                idle
            }
        }
        // The one-second clock only runs while this pane is on screen.
        .onAppear { model.beginFastUpdates() }
        .onDisappear { model.endFastUpdates() }
    }

    // MARK: - Idle

    private var idle: some View {
        VStack(spacing: Theme.Space.l) {
            Image(systemName: "target")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(Theme.tertiaryLabel)
            VStack(spacing: Theme.Space.xs) {
                Text(Format.greeting(userName))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.label)
                Text("Start a focused session, then give yourself an honest review when it ends.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            Button("Start a session", action: onStart)
                .accessibilityIdentifier("focus.start")
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("n", modifiers: .command)

            if !personalNote.isEmpty {
                Text(personalNote)
                    .font(Theme.Font.body)
                    .italic()
                    .foregroundStyle(Theme.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                    .padding(.top, Theme.Space.s)
            }
        }
        .padding(Theme.Space.xxl)
    }

    // MARK: - Running

    private func running(_ session: WorkSession) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = session.elapsed(at: context.date)
            let remaining = session.remaining(at: context.date)
            let progress = min(1, elapsed / max(1, session.plannedDuration))

            VStack(spacing: Theme.Space.xl) {
                VStack(spacing: Theme.Space.xs) {
                    Text(session.category.uppercased())
                        .font(Theme.Font.sectionHeader)
                        .tracking(0.8)
                        .foregroundStyle(CategoryPalette.color(for: session.category))
                    Text(session.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.label)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                ring(progress: progress, remaining: remaining, session: session)

                controls(session)
            }
            .padding(Theme.Space.xxl)
        }
    }

    private func ring(progress: Double, remaining: TimeInterval, session: WorkSession) -> some View {
        ZStack {
            Circle()
                .stroke(Theme.hairline, lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    CategoryPalette.color(for: session.category),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)

            VStack(spacing: Theme.Space.xs) {
                Text(Format.clock(remaining))
                    .font(Theme.Font.timer)
                    .foregroundStyle(Theme.label)
                Text(statusLine(session, remaining: remaining))
                    .font(Theme.Font.caption)
                    .foregroundStyle(remaining <= 0 ? .orange : Theme.secondaryLabel)
            }
        }
        .frame(width: 260, height: 260)
    }

    private func statusLine(_ session: WorkSession, remaining: TimeInterval) -> String {
        if session.status == .paused { return "Paused" }
        if remaining <= 0 { return "Time's up — finish when you're ready" }
        return "of \(session.plannedMinutes) minutes"
    }

    private func controls(_ session: WorkSession) -> some View {
        VStack(spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.m) {
                if session.status == .paused {
                    Button("Resume") { model.resumeSession() }
                        .accessibilityIdentifier("focus.resume")
                        .buttonStyle(.bordered)
                } else {
                    Button("Pause") { model.pauseSession() }
                        .accessibilityIdentifier("focus.pause")
                        .buttonStyle(.bordered)
                }
                Button("Finish", action: onFinish)
                    .accessibilityIdentifier("focus.finish")
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.onAccent)
            }
            .controlSize(.large)

            if session.remaining() <= 0 {
                Button("Add 5 minutes") { model.extendSession(byMinutes: 5) }
                    .accessibilityIdentifier("focus.addFiveMinutes")
                    .buttonStyle(.link)
                    .font(Theme.Font.caption)
            }
        }
    }
}
