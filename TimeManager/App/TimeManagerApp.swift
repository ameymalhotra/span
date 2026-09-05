import SwiftUI
import SwiftData
import AppKit

@main
struct TimeManagerApp: App {
    private let container: ModelContainer = {
        let schema = Schema([WorkSession.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: configuration)
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)

        MenuBarExtra("Time Manager", systemImage: "timer") {
            Button("Open Time Manager") { NSApplication.shared.activate(ignoringOtherApps: true) }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .modelContainer(container)
}

}
