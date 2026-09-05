import SwiftUI

struct StartSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var category = "General"
    @State private var minutes = 50
    let onStart: (String, String, Int) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("What are you working on?") {
                    TextField("e.g. Build TimeManager", text: $title)
                    TextField("Category", text: $category)
                }
                Section("How long?") {
                    Picker("Duration", selection: $minutes) {
                        ForEach([25, 50, 75, 90], id: \.self) { minutes in
                            Text("\(minutes) minutes").tag(minutes)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("New session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        onStart(title.trimmingCharacters(in: .whitespacesAndNewlines), category.trimmingCharacters(in: .whitespacesAndNewlines), minutes)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
