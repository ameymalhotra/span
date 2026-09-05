import SwiftUI

/// The toolbar's day control: a label that names the day and opens a calendar.
struct DateNavigator: View {
    @Binding var date: Date
    @State private var isPickerPresented = false

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Button {
                isPickerPresented = true
            } label: {
                HStack(spacing: Theme.Space.xs) {
                    Text(Format.dayTitle(date))
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            .buttonStyle(.accessoryBar)
            .popover(isPresented: $isPickerPresented) {
                DatePicker("Day", selection: $date, in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(Theme.Space.m)
            }

            if !Calendar.current.isDateInToday(date) {
                Button("Today") { date = Calendar.current.startOfDay(for: .now) }
                    .buttonStyle(.accessoryBar)
            }
        }
    }
}
