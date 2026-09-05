import SwiftData
import SwiftUI

/// Rename, recolour, add and remove the categories offered when starting a
/// session or naming a block.
struct CategoryManager: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TimeCategory.sortIndex) private var categories: [TimeCategory]

    @State private var editingColorFor: TimeCategory?
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(categories) { category in
                row(category)
            }

            Divider().padding(.vertical, Theme.Space.xs)

            HStack(spacing: Theme.Space.s) {
                TextField("Add a category — school work, admin…", text: $newName)
                    .accessibilityIdentifier("categories.newName")
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .accessibilityIdentifier("categories.add")
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func row(_ category: TimeCategory) -> some View {
        HStack(spacing: Theme.Space.m) {
            Button {
                editingColorFor = category
            } label: {
                Circle()
                    .fill(category.resolvedColor)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("category.colour.\(category.name)")
            .help("Change colour")

            TextField("Name", text: Binding(
                get: { category.name },
                set: { category.name = $0; refresh() }
            ))
            .textFieldStyle(.plain)
            .font(Theme.Font.body)

            Spacer()

            Button {
                context.delete(category)
                refresh()
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(Theme.tertiaryLabel)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("category.delete.\(category.name)")
            // Deleting a category leaves the records that used it alone — they
            // keep the name and fall back to a hashed colour.
            .help("Remove — sessions already filed here keep their name")
        }
        .popover(item: $editingColorFor) { editing in
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text(editing.name).font(.system(size: 13, weight: .semibold))
                SwatchGrid(
                    slot: Binding(
                        get: { editing.colorSlot },
                        set: { editing.colorSlot = $0; editing.colorHex = nil; refresh() }
                    ),
                    custom: Binding(
                        get: { editing.colorHex.map { Color(hexString: $0) } },
                        set: { editing.colorHex = $0?.hexString; refresh() }
                    )
                )
            }
            .padding(Theme.Space.l)
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let used = Set(categories.filter { $0.colorHex == nil }.map(\.colorSlot))
        let slot = CategoryPalette.swatches.first { !used.contains($0.slot) }?.slot ?? 0
        context.insert(TimeCategory(name: name, colorSlot: slot,
                                    sortIndex: (categories.map(\.sortIndex).max() ?? 0) + 1))
        newName = ""
        refresh()
    }

    private func refresh() {
        try? context.save()
        CategoryPalette.updateRegistry(categories)
    }
}
