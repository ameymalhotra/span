import SwiftData
import SwiftUI

/// Picks a category, showing each one's colour, and can create one inline.
struct CategoryPicker: View {
    @Environment(\.modelContext) private var context
    @Binding var selection: String

    @Query(sort: \TimeCategory.sortIndex) private var categories: [TimeCategory]
    @State private var isPicking = false

    var body: some View {
        Button {
            isPicking = true
        } label: {
            HStack(spacing: Theme.Space.s) {
                Circle()
                    .fill(CategoryPalette.color(for: selection))
                    .frame(width: 10, height: 10)
                Text(selection.isEmpty ? "Uncategorised" : selection)
                    .foregroundStyle(selection.isEmpty ? Theme.tertiaryLabel : Theme.label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Theme.Space.xs)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryLabel)
            }
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, 4)
            // Fills whatever width it is given rather than shrinking to its
            // label, so a column of pickers lines up.
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.hairline, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPicking) {
            CategoryList(selection: $selection, onPicked: { isPicking = false })
        }
    }
}

/// The list itself. A plain view rather than a `Menu`: macOS renders SF Symbols
/// in menus as template images, so a coloured dot came out monochrome and every
/// category looked identical.
private struct CategoryList: View {
    @Environment(\.modelContext) private var context
    @Binding var selection: String
    let onPicked: () -> Void

    @Query(sort: \TimeCategory.sortIndex) private var categories: [TimeCategory]
    @State private var isCreating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isCreating {
                CategoryCreator(
                    existing: categories,
                    onCancel: { isCreating = false },
                    onCreate: { name in
                        selection = name
                        onPicked()
                    }
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(categories) { category in
                            row(category)
                        }
                    }
                }
                .frame(maxHeight: 260)

                Divider()

                Button {
                    isCreating = true
                } label: {
                    Label("New Category…", systemImage: "plus")
                        .font(Theme.Font.body)
                        .padding(.horizontal, Theme.Space.m)
                        .padding(.vertical, Theme.Space.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 260)
    }

    private func row(_ category: TimeCategory) -> some View {
        Button {
            selection = category.name
            onPicked()
        } label: {
            HStack(spacing: Theme.Space.s) {
                Circle()
                    .fill(category.resolvedColor)
                    .frame(width: 10, height: 10)
                Text(category.name)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.label)
                Spacer()
                if selection == category.name {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Name plus colour for a new category: ten presets, or the system colour
/// wheel when none of them fit.
struct CategoryCreator: View {
    @Environment(\.modelContext) private var context
    let existing: [TimeCategory]
    var onCancel: () -> Void
    var onCreate: (String) -> Void

    @State private var name = ""
    @State private var slot = 0
    @State private var custom: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("New category")
                .font(.system(size: 13, weight: .semibold))

            TextField("Name — school work, admin…", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)

            SwatchGrid(slot: $slot, custom: $custom)

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Add", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Theme.Space.l)
        .onAppear { slot = nextFreeSlot() }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let category = TimeCategory(name: trimmed, colorSlot: slot,
                                    sortIndex: (existing.map(\.sortIndex).max() ?? 0) + 1)
        category.colorHex = custom?.hexString
        context.insert(category)
        try? context.save()
        CategoryPalette.updateRegistry(existing + [category])
        onCreate(trimmed)
    }

    /// Prefers a colour nothing else uses, so a new category is distinguishable
    /// without the user having to think about it.
    private func nextFreeSlot() -> Int {
        let used = Set(existing.filter { $0.colorHex == nil }.map(\.colorSlot))
        return CategoryPalette.swatches.first { !used.contains($0.slot) }?.slot ?? 0
    }
}

/// Ten preset colours plus a wheel.
struct SwatchGrid: View {
    @Binding var slot: Int
    @Binding var custom: Color?

    private let columns = Array(repeating: GridItem(.fixed(22), spacing: 8), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(CategoryPalette.swatches) { swatch in
                    Button {
                        slot = swatch.slot
                        custom = nil
                    } label: {
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 20, height: 20)
                            .overlay {
                                if custom == nil && slot == swatch.slot {
                                    Circle().strokeBorder(Theme.label.opacity(0.65), lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(swatch.name)
                }
            }

            HStack(spacing: Theme.Space.s) {
                ColorPicker(selection: Binding(
                    get: { custom ?? CategoryPalette.color(slot: slot) },
                    set: { custom = $0 }
                ), supportsOpacity: false) {
                    Text("Custom colour")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                if custom != nil {
                    Button("Use a preset") { custom = nil }
                        .buttonStyle(.link)
                        .font(Theme.Font.caption)
                }
            }
        }
    }
}
