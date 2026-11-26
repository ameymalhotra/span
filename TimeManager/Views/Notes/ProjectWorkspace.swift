import SwiftUI

/// A project keeps its handoff history and its longer-lived notes together.
/// The switch avoids squeezing a fourth column into the main app window.
struct ProjectWorkspace<LogContent: View>: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @Bindable var tab: LogTab
    @ViewBuilder let log: () -> LogContent
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(tab.name).font(.headline).lineLimit(1)
                Spacer()
                Picker("Project view", selection: Binding(
                    get: { tab.showsNotes },
                    set: { value in
                        do {
                            try model.notebooks.flushAll()
                            tab.showsNotes = value
                            try context.save()
                        } catch { self.error = error.localizedDescription }
                    }
                )) {
                    Text("Log").tag(false)
                    Text("Notes").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 160)
                .accessibilityIdentifier("notes.projectView")
            }.padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            if tab.showsNotes { NotebookView(tab: tab) }
            else { log() }
        }
        .onDisappear { try? model.notebooks.flushAll() }
        .alert("Couldn’t save notes", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }
}
