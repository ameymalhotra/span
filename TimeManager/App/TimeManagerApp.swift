import AppKit
import SwiftData
import SwiftUI

@main
struct TimeManagerApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private let container: ModelContainer
    @State private var model: AppModel

    init() {
        let container = ModelStack.makeContainer()
        self.container = container
        _model = State(initialValue: AppModel(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { delegate.configure(with: model) }
        }
        .modelContainer(container)
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands { commands }

        Settings {
            SettingsScene()
                .environment(model)
                .modelContainer(container)
        }

        MenuBarExtra {
            MenuBarPanelView()
                .environment(model)
                .modelContainer(container)
                .frame(width: 300)
        } label: {
            // Published as a plain string so a tick that doesn't change the
            // visible text doesn't redraw the menu bar.
            Label(model.activeSession == nil ? "" : model.sessionClock, systemImage: "timer")
        }
        .menuBarExtraStyle(.window)
    }

    @CommandsBuilder
    private var commands: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(after: .toolbar) {
            Button("Today") {
                model.selectedDate = Calendar.current.startOfDay(for: .now)
            }
            .keyboardShortcut("t", modifiers: .command)
        }
    }
}

/// Owns the pieces that have to exist outside the SwiftUI scene graph: the
/// floating HUD panel, and the launch/termination hooks.
///
/// Main-actor isolated, which also makes it `Sendable` — the KVO callback below
/// hops back onto the main actor and would otherwise be sending a non-Sendable
/// `self` across isolation domains.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var model: AppModel?
    private var hud: HUDController?
    private var hudObserver: NSKeyValueObservation?

    func configure(with model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        model.start()

        let hud = HUDController(model: model)
        self.hud = hud
        applyHUDVisibility()

        // The HUD is toggled from three places — settings, the status bar and
        // the pill's own menu — so all of them write one default and this
        // observes it, rather than each one holding a reference to the panel.
        hudObserver = UserDefaults.standard.observe(\.hudVisible, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.applyHUDVisibility() }
        }
    }

    private func applyHUDVisibility() {
        let wanted = UserDefaults.standard.object(forKey: "hud.visible") as? Bool ?? true
        wanted ? hud?.show() : hud?.hide()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
    }

    /// Closing the window leaves the app running: it is still tracking, and the
    /// menu bar item and HUD are still doing their job.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

extension UserDefaults {
    /// Key-path access for the KVO observation above.
    @objc dynamic var hudVisible: Bool { bool(forKey: "hud.visible") }
}
