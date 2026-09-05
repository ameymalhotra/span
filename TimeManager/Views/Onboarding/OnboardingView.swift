import SwiftUI

/// First-run setup: a few questions whose answers actually configure the app,
/// rather than a tour that gets clicked through.
struct OnboardingView: View {

    @AppStorage("userName") private var userName = ""
    @AppStorage("personalNote") private var personalNote = ""
    @AppStorage("dailyFocusTargetMinutes") private var targetMinutes = 300
    @AppStorage("defaultSessionMinutes") private var defaultSessionMinutes = 60

    @Environment(AppModel.self) private var model

    let onFinish: (_ openGuide: Bool) -> Void

    @State private var step = 0
    @State private var enableTracking = true
    @FocusState private var nameFocused: Bool

    private static let targets = [120, 180, 240, 300, 360, 420, 480]
    private static let stepCount = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .frame(height: 300, alignment: .top)
                .padding(.horizontal, Theme.Space.xxl)
                .padding(.top, Theme.Space.xxl)

            Spacer(minLength: 0)
            Divider()
            footer
        }
        .frame(width: 520, height: 420)
        .background(Theme.canvas)
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: welcome
        case 1: target
        case 2: sessionLength
        case 3: tracking
        default: note
        }
    }

    private var welcome: some View {
        step("Welcome to Span", "Span records where your time actually goes — the sessions you start, the blocks you write down, and what your Mac was doing in between.") {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("What should Span call you?")
                    .font(Theme.Font.body)
                TextField("Your name", text: $userName)
                    .accessibilityIdentifier("onboarding.userName")
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .focused($nameFocused)
                    .onSubmit(advance)
                Text("Only ever shown to you, on this Mac.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.tertiaryLabel)
            }
            .onAppear { nameFocused = true }
        }
    }

    private var target: some View {
        step("How much focused work is a good day?",
             "Not your working hours — the part that is genuinely heads-down. Most people land between three and five. You can change it later.") {
            Picker("", selection: $targetMinutes) {
                ForEach(Self.targets, id: \.self) { minutes in
                    Text(Format.compact(TimeInterval(minutes * 60))).tag(minutes)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 380)
        }
    }

    private var sessionLength: some View {
        step("How long do you usually work in one go?",
             "This becomes the length that is pre-selected when you start a session.") {
            DurationPicker(minutes: $defaultSessionMinutes, showsSummary: false)
                .frame(width: 380)
        }
    }

    private var tracking: some View {
        step("Should Span watch what you work in?",
             "It asks macOS which app is in front and how long since you last touched the keyboard. It cannot see what you type or what is on screen, and nothing leaves this Mac.") {
            Toggle(isOn: $enableTracking) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Track application activity").font(Theme.Font.body)
                    Text("You can pause it any time from the status bar.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            .toggleStyle(.switch)
        }
    }

    private var note: some View {
        step(greetingTitle,
             "A line to keep in front of you — a reason, a reminder, something you are working towards. It appears when you start a session. Leave it empty if you would rather not.") {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                TextField("Finish the thing before starting the next one.",
                          text: $personalNote, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...3)
                    .frame(width: 380)
                Text("Editable any time in Settings.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.tertiaryLabel)
            }
        }
    }

    private var greetingTitle: String {
        let name = userName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Anything you want to tell yourself?" : "Anything you want to tell yourself, \(name)?"
    }

    private func step(_ title: String, _ detail: String,
                      @ViewBuilder control: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            control()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Theme.Space.m) {
            HStack(spacing: 5) {
                ForEach(0..<Self.stepCount, id: \.self) { index in
                    Circle()
                        .fill(index == step ? Theme.accent : Theme.tertiaryLabel.opacity(0.35))
                        .frame(width: 5, height: 5)
                }
            }

            Spacer()

            if step > 0 {
                Button("Back") { step -= 1 }
                    .accessibilityIdentifier("onboarding.back")
            }
            Button(step == Self.stepCount - 1 ? "Start using Span" : "Continue") {
                advance()
            }
            .accessibilityIdentifier("onboarding.continue")
            .keyboardShortcut(.defaultAction)
        }
        .padding(Theme.Space.l)
    }

    private func advance() {
        guard step < Self.stepCount - 1 else {
            finish()
            return
        }
        step += 1
    }

    private func finish() {
        userName = userName.trimmingCharacters(in: .whitespaces)
        personalNote = personalNote.trimmingCharacters(in: .whitespacesAndNewlines)
        model.tracker.isPaused = !enableTracking
        onFinish(true)
    }
}
