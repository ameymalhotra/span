import SwiftUI

/// Contents of the menu bar item's popover.
struct MenuBarPanelView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if let session = model.activeSession {
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
                    Button("Finish") { model.finishSession() }
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
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { !($0 is HUDPanel) }?.makeKeyAndOrderFront(nil)
            }
            Button("Quit") { NSApp.terminate(nil) }
                .accessibilityIdentifier("menuBar.quit")
        }
        .font(Theme.Font.body)
        .padding(Theme.Space.l)
        .onAppear { model.beginFastUpdates() }
        .onDisappear { model.endFastUpdates() }
    }
}
