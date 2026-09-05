import SwiftData
import SwiftUI

/// Picks a category by name, showing its colour, and can create one inline.
struct CategoryPicker: View {
    @Environment(\.modelContext) private var context
    @Binding var selection: String

    @Query(sort: \TimeCategory.sortIndex) private var categories: [TimeCategory]
    @State private var isAdding = false
    @State private var newName = ""
    @State private var newSlot = 0

    var body: some View {
        Menu {
            ForEach(categories) { category in
                Button {
                    selection = category.name
                } label: {
                    Label {
                        Text(category.name)
                    } icon: {
                        Image(systemName: selection == category.name ? "checkmark" : "circle.fill")
                    }
                }
            }
            Divider()
            Button("New Category…") {
                newSlot = nextFreeSlot()
                isAdding = true
            }
        } label: {
            HStack(spacing: Theme.Space.s) {
                Circle()
                    .fill(CategoryPalette.color(for: selection))
                    .frame(width: 9, height: 9)
                Text(selection.isEmpty ? "Uncategorised" : selection)
                    .foregroundStyle(selection.isEmpty ? Theme.tertiaryLabel : Theme.label)
                Spacer(minLength: 0)
            }
        }
        .menuStyle(.borderlessButton)
        .popover(isPresented: $isAdding) {
            newCategoryForm
        }
    }

    private var newCategoryForm: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("New category")
                .font(.system(size: 13, weight: .semibold))
            TextField("Name", text: $newName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            SwatchRow(selection: $newSlot)
            HStack {
                Button("Cancel") { isAdding = false; newName = "" }
                Spacer()
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Theme.Space.l)
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let category = TimeCategory(name: name, colorSlot: newSlot,
                                    sortIndex: (categories.map(\.sortIndex).max() ?? 0) + 1)
        context.insert(category)
        try? context.save()
        CategoryPalette.updateRegistry(categories + [category])
        selection = name
        newName = ""
        isAdding = false
    }

    /// Prefers a colour nothing else is using, so a new category is
    /// distinguishable without the user having to think about it.
    private func nextFreeSlot() -> Int {
        let used = Set(categories.map(\.colorSlot))
        return CategoryPalette.swatches.first { !used.contains($0.slot) }?.slot
            ?? ((categories.map(\.colorSlot).max() ?? 0) + 1) % CategoryPalette.swatches.count
    }
}

/// The seven palette colours as selectable dots.
struct SwatchRow: View {
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(CategoryPalette.swatches) { swatch in
                Button {
                    selection = swatch.slot
                } label: {
                    Circle()
                        .fill(swatch.color)
                        .frame(width: 18, height: 18)
                        .overlay {
                            if selection == swatch.slot {
                                Circle().strokeBorder(Theme.label.opacity(0.6), lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(swatch.name)
            }
        }
    }
}
