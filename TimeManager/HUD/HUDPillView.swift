import AppKit
import SwiftUI

/// The floating capsule: three read-only stats and a menu.
struct HUDPillView: View {
    @Environment(AppModel.self) private var model
    let controller: HUDController

    @AppStorage("hud.visible") private var isVisible = true

    var body: some View {
        HStack(spacing: 0) {
            HUDStat(value: model.sinceBreakText, top: "TIME SINCE", bottom: "LAST BREAK")
            HUDStat(value: primaryValue, top: primaryTop, bottom: primaryBottom, tint: Theme.accent)
            HUDStat(value: model.percentOfTargetText, top: "PERCENT", bottom: "OF TARGET")

            Capsule()
                .fill(.white.opacity(0.16))
                .frame(width: 1, height: 20)
                .padding(.horizontal, Theme.Space.m)

            Menu {
                menuContents
            } label: {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.white.opacity(0.8))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26)
        }
        .padding(.horizontal, 20)
        .frame(height: 46)
        .background {
            // `.hudWindow` is the system's own HUD material. Paired with the
            // panel's vibrantDark appearance it stays a dark, legible slab over
            // a white wallpaper as readily as over a dark one — which a
            // hand-mixed translucent fill does not.
            VisualEffectView(material: .hudWindow, blending: .behindWindow)
        }
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        // The window is a rectangle and the pill is a capsule; this keeps the
        // corner slivers from swallowing clicks meant for what is behind.
        .contentShape(Capsule())
    }

    /// The middle stat counts down while a session runs and reports the day's
    /// total otherwise — the number you actually want at each moment.
    private var primaryValue: String {
        model.activeSession == nil ? model.focusTodayText : model.sessionClock
    }
    private var primaryTop: String { model.activeSession == nil ? "FOCUS" : "SESSION" }
    private var primaryBottom: String { model.activeSession == nil ? "TODAY" : "REMAINING" }

    @ViewBuilder
    private var menuContents: some View {
        if let session = model.activeSession {
            if session.status == .paused {
                Button("Resume Session") { model.resumeSession() }
            } else {
                Button("Pause Session") { model.pauseSession() }
            }
            Button("Finish Session") { model.finishSession() }
            Divider()
        }
        Button("Open Time Manager") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0 is HUDPanel == false }?.makeKeyAndOrderFront(nil)
        }
        Divider()
        Toggle("Pause Tracking", isOn: Binding(
            get: { model.tracker.isPaused },
            set: { model.tracker.isPaused = $0 }
        ))
        Divider()
        Button("Reset Position") { controller.resetPosition() }
        Button("Hide HUD") { isVisible = false }
        Divider()
        Button("Quit Time Manager") { NSApp.terminate(nil) }
    }
}

/// One stat: a value beside a two-line uppercase caption.
private struct HUDStat: View {
    let value: String
    let top: String
    let bottom: String
    var tint: Color?

    var body: some View {
        HStack(spacing: 8) {
            Text(value)
                .font(.system(size: 17, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(tint ?? .white.opacity(0.92))
            VStack(alignment: .leading, spacing: -1) {
                Text(top)
                Text(bottom)
            }
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(.white.opacity(0.45))
        }
        // A fixed slot so a changing digit never reflows its neighbours.
        .frame(minWidth: 150, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
    }
}
