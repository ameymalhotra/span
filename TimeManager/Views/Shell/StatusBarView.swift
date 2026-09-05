import SwiftUI

/// The persistent bar along the bottom of the window: what is being tracked
/// right now on the left, the day's totals in the middle, controls on the right.
struct StatusBarView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("hud.visible") private var isHUDVisible = true

    var body: some View {
        ZStack {
            Text("Focus \(model.focusTodayText) · \(model.percentOfTargetText) of target")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.secondaryLabel)
                .lineLimit(1)

            HStack(spacing: Theme.Space.m) {
                HStack(spacing: Theme.Space.s) {
                    Circle()
                        .fill(indicatorColor)
                        .frame(width: 7, height: 7)
                    Text(statusText)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(1)
                }

                Spacer(minLength: Theme.Space.l)

                Toggle(isOn: Binding(
                    get: { !model.tracker.isPaused },
                    set: { model.tracker.isPaused = !$0 }
                )) {
                    Text("Tracking")
                        .font(Theme.Font.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Pause or resume automatic activity tracking")
                .accessibilityIdentifier("status.trackingToggle")

                if case .available(let version, _, _) = model.updates.state {
                    Button {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Update \(version)")
                        }
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Version \(version) is available — open Settings to install it")
                }

                Button {
                    isHUDVisible.toggle()
                } label: {
                    Image(systemName: isHUDVisible ? "rectangle.topthird.inset.filled" : "rectangle")
                }
                .buttonStyle(.accessoryBar)
                .help(isHUDVisible ? "Hide the floating HUD" : "Show the floating HUD")
                .accessibilityIdentifier("status.hudToggle")
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(height: 30)
        .background(VisualEffectView(material: .titlebar))
    }

    private var indicatorColor: Color {
        if model.tracker.isPaused { return Theme.tertiaryLabel }
        if model.tracker.isIdle { return .orange }
        return Theme.accent
    }

    private var statusText: String {
        if model.tracker.isPaused { return "Tracking paused" }
        if model.tracker.isIdle { return "Away" }
        let app = model.tracker.currentAppName
        return app.isEmpty ? "Waiting for activity" : app
    }
}
