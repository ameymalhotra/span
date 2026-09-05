import SwiftUI
import SwiftData

struct ReflectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let session: WorkSession
    @State private var focus = 3
    @State private var honestMinutes = 0
    @State private var distractions = 0
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Be kind and honest—this is for you, not a scorecard.")
                        .foregroundStyle(.secondary)
                }
                Section("How focused were you?") {
                    Picker("Focus", selection: $focus) {
                        ForEach(1...5, id: \.self) { value in Text("\(value) / 5").tag(value) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("How much felt like real work?") {
                    Stepper("\(honestMinutes) minutes", value: $honestMinutes, in: 0...max(1, Int(session.elapsed() / 60)))
                }
                Section("Meaningful distractions") {
                    Stepper("\(distractions)", value: $distractions, in: 0...20)
                }
                Section("Anything worth noting?") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .onAppear { honestMinutes = Int(session.elapsed() / 60) }
            .navigationTitle("How did it go?")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        session.focusRating = focus
                        session.honestWorkMinutes = honestMinutes
                        session.distractions = distractions
                        session.reflection = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
