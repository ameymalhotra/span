import SwiftUI

/// Contents of the menu bar item's popover.
struct MenuBarPanelView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if model.isOnBreak {
                VStack(alignment: .leading, spacing: 2) {
                    Text("On a break")
                        .font(.system(size: 13, weight: .semibold))
                    Text(model.breakClock + " left")
                        .font(Theme.Font.caption.monospacedDigit())
                        .foregroundStyle(Theme.secondaryLabel)
                }
                Button(model.sessionPausedForBreak ? "Back to work" : "End break") {
                    model.endBreak()
                }
                .accessibilityIdentifier("menuBar.endBreak")
                .buttonStyle(.borderedProminent)
                .tint(Theme.rest)
                .foregroundStyle(.white)
            } else if let session = model.activeSession {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(model.sessionClock + " remaining")
                        .font(Theme.Font.caption.monospacedDigit())
                        .foregroundStyle(Theme.secondaryLabel)
                }
                HStack(spacing: Theme.Space.s) {
                    if session.status == .paused {
                        Button("Resume") { model.resumeSession() }
                            .accessibilityIdentifier("menuBar.resume")
                    } else {
                        Button("Pause") { model.pauseSession() }
                            .accessibilityIdentifier("menuBar.pause")
                    }
                    Button("Finish") {
                        model.finishSession()
                        // The review sheet lives in the main window, which may
                        // not even be open from here.
                        openMainWindow()
                    }
                        .accessibilityIdentifier("menuBar.finish")
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .foregroundStyle(Theme.onAccent)
                }
            } else {
                Text("No session running")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.secondaryLabel)
            }

            Divider()

            LabeledContent("Focus today", value: model.focusTodayText)
            LabeledContent("Of target", value: model.percentOfTargetText)
            LabeledContent("Now", value: model.tracker.isPaused
                           ? "Tracking paused"
                           : (model.tracker.isIdle ? "Away" : model.tracker.currentAppName))

            Divider()

            Button("Open Span") {
                openMainWindow()
            }
            Button("Quit") { NSApp.terminate(nil) }
                .accessibilityIdentifier("menuBar.quit")
        }
        .font(Theme.Font.body)
        .padding(Theme.Space.l)
        .onAppear { model.beginFastUpdates() }
        .onDisappear { model.endFastUpdates() }
    }

    /// Fronts the main window, which is where sheets are presented and may be
    /// closed while the menu bar item is still around.
    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { !($0 is HUDPanel) }?.makeKeyAndOrderFront(nil)
    }
}
