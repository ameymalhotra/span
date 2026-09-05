import SwiftUI

struct SidebarView: View {
    @Binding var selection: Destination

    var body: some View {
        List(selection: $selection) {
            Section("Track") {
                row(.focus)
                row(.timeline)
            }
            Section("Review") {
                row(.day)
                row(.insights)
                row(.categories)
            }
            Section {
                row(.settings)
            }
        }
        // `.sidebar` already carries the system's vibrancy — and on recent
        // macOS its Liquid Glass treatment. Painting a background over it
        // fights the platform rather than matching it.
        .listStyle(.sidebar)
    }

    private func row(_ destination: Destination) -> some View {
        Label(destination.title, systemImage: destination.symbol)
            .tag(destination)
    }
}
