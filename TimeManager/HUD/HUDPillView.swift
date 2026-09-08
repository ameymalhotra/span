import AppKit
import SwiftUI

/// The floating capsule: three read-only stats and a menu.
///
/// This is the one surface that sits over the user's other windows all day, so
/// it is trimmed to the smallest thing that still reads at a glance — one-line
/// captions, a ring in place of a third caption, and no fixed-width slots
/// beyond what monospaced digits already guarantee. The palette stays the
/// app's: white for the read-outs, teal for the live number and the ring.
struct HUDPillView: View {
    @Environment(AppModel.self) private var model
    let controller: HUDController

    @AppStorage("hud.visible") private var isVisible = true
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            HUDStat(
                value: model.sinceBreakText,
                caption: "SINCE BREAK",
                minValueWidth: 44
            )
            .help("Time since your last break")

            divider

            HUDStat(
                value: primaryValue,
                caption: primaryCaption,
                tint: model.sessionIsOvertime ? Theme.HUD.overtime : Theme.HUD.accent,
                pulses: model.activeSession?.status == .active,
                minValueWidth: 48
            )
            .help(model.sessionIsOvertime
                  ? "This session has run past its planned end"
                  : model.activeSession == nil
                    ? "Focused time so far today"
                    : "Time remaining in this session")

            divider

            HUDTarget(fraction: model.focusFraction, text: model.percentOfTargetText)
                .help("Progress toward today's focus target")

            menuButton
                .padding(.leading, Theme.Space.m)
        }
        .padding(.leading, Theme.Space.l)
        .padding(.trailing, 7)
        .frame(height: 40)
        .background {
            // `.hudWindow` is the system's own HUD material. Paired with the
            // panel's vibrantDark appearance it stays a dark, legible slab over
            // a white wallpaper as readily as over a dark one — which a
            // hand-mixed translucent fill does not.
            VisualEffectView(material: .hudWindow, blending: .behindWindow)
        }
        .clipShape(Capsule())
        .overlay {
            Capsule().strokeBorder(
                .white.opacity(isHovering ? 0.24 : 0.14),
                lineWidth: 0.75
            )
        }
        // The window is a rectangle and the pill is a capsule; this keeps the
        // corner slivers from swallowing clicks meant for what is behind.
        .contentShape(Capsule())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.18), value: isHovering)
    }

    private var divider: some View {
        Capsule()
            .fill(Theme.HUD.line)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 13)
    }

    private var menuButton: some View {
        Menu {
            menuContents
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(isHovering ? 0.9 : 0.7))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(isHovering ? 0.12 : 0.06)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 26, height: 26)
    }

    /// The middle stat counts down while a session runs and reports the day's
    /// total otherwise — the number you actually want at each moment.
    private var primaryValue: String {
        if model.isOnBreak { return model.breakClock }
        return model.activeSession == nil ? model.focusTodayText : model.sessionClock
    }
    private var primaryCaption: String {
        // A break is what is happening, so it takes the live number — otherwise
        // the pill counts down a session that is paused behind it.
        if model.isOnBreak { return "BREAK" }
        if model.sessionIsOvertime { return "TIME UP" }
        return model.activeSession == nil ? "FOCUS TODAY" : "REMAINING"
    }

    @ViewBuilder
    private var menuContents: some View {
        if model.isOnBreak {
            Button("End Break") { model.endBreak() }
                .accessibilityIdentifier("hud.endBreak")
            Divider()
        }
        if let session = model.activeSession {
            if session.status == .paused {
                Button("Resume Session") { model.resumeSession() }
                    .accessibilityIdentifier("hud.resume")
            } else {
                Button("Pause Session") { model.pauseSession() }
                    .accessibilityIdentifier("hud.pause")
            }
            Button("Finish Session") {
                model.finishSession()
                // The review sheet lives in the main window.
                openMainWindow()
            }
            .accessibilityIdentifier("hud.finish")
            Divider()
        }
        Button("Open Span") { openMainWindow() }
        Divider()
        Toggle("Pause Tracking", isOn: Binding(
            get: { model.tracker.isPaused },
            set: { model.tracker.isPaused = $0 }
        ))
        Divider()
        Button("Reset Position") { controller.resetPosition() }
            .accessibilityIdentifier("hud.resetPosition")
        Button("Hide HUD") { isVisible = false }
            .accessibilityIdentifier("hud.hide")
        Divider()
        Button("Quit Span") { NSApp.terminate(nil) }
            .accessibilityIdentifier("hud.quit")
    }

    /// Fronts the main window. The HUD floats above every app and presents
    /// nothing itself, so anything needing a sheet has to go through there.
    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { !($0 is HUDPanel) }?.makeKeyAndOrderFront(nil)
    }
}

/// One stat: a value beside a single-line uppercase caption.
private struct HUDStat: View {
    let value: String
    let caption: String
    var tint: Color = Theme.HUD.value
    var pulses = false
    /// The value grows leftward out of this slot, so the caption beside it
    /// holds still while the digits change.
    var minValueWidth: CGFloat

    var body: some View {
        HStack(spacing: 7) {
            if pulses { PulseDot(color: tint) }
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(tint)
                .frame(minWidth: minValueWidth, alignment: .trailing)
            Text(caption)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.HUD.caption)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// The day's target as a ring plus its percentage.
///
/// The ring replaces the caption the other two stats carry: a sweep reads as
/// progress on sight, where "3% / OF TARGET" spent two lines saying the same.
private struct HUDTarget: View {
    let fraction: Double
    let text: String

    private var isComplete: Bool { fraction >= 1 }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(Theme.HUD.line, lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: min(1, max(0, fraction)))
                    .stroke(Theme.HUD.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    // Start the sweep at twelve o'clock rather than three.
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 17, height: 17)
            .animation(.easeOut(duration: 0.45), value: fraction)

            // The number goes teal only once the ring has closed, which is the
            // one moment in the day worth marking.
            Text(text)
                .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(isComplete ? Theme.HUD.accent : Theme.HUD.value)
                .frame(minWidth: 34, alignment: .leading)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// A slow breath on the accent dot: the only moving thing on the pill, so a
/// running session announces itself without spending a word on it.
private struct PulseDot: View {
    let color: Color
    @State private var lit = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(lit ? 1 : 0.35)
            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: lit)
            .onAppear { lit = true }
    }
}
