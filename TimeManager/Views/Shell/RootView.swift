import SwiftData
import SwiftUI

enum Destination: String, Hashable, CaseIterable, Identifiable {
    case focus, timeline, day, insights, categories, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: "Focus"
        case .timeline: "Timeline"
        case .day: "Day"
        case .insights: "Insights"
        case .settings: "Settings"
        case .categories: "Categories"
        }
    }

    var symbol: String {
        switch self {
        case .focus: "target"
        case .timeline: "calendar.day.timeline.left"
        case .day: "square.grid.2x2"
        case .insights: "chart.bar"
        case .settings: "gearshape"
        case .categories: "circle.grid.3x3"
        }
    }
}

struct RootView: View {

    @Environment(AppModel.self) private var model

    @State private var destination: Destination = .focus
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isStartingSession = false
    @State private var reflecting: WorkSession?
    @AppStorage("timeline.hourHeight") private var hourHeight: Double = 60

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(selection: $destination)
                    .navigationSplitViewColumnWidth(min: 190, ideal: 216, max: 280)
            } detail: {
                detail(selectedDate: $model.selectedDate)
            }
            Divider()
            StatusBarView()
        }
        .frame(minWidth: 940, minHeight: 600)
        .sheet(isPresented: $isStartingSession) {
            StartSessionView { title, category, minutes in
                model.startSession(title: title, category: category, minutes: minutes)
            }
        }
        .sheet(item: $reflecting) { session in
            ReflectionView(session: session)
        }
    }

    @ViewBuilder
    private func detail(selectedDate: Binding<Date>) -> some View {
        Group {
            if destination == .timeline {
                // The timeline earns the whole pane when it is the destination;
                // elsewhere it stays alongside as persistent context.
                timeline(for: selectedDate.wrappedValue)
            } else {
                HSplitView {
                    centerPane
                        .frame(minWidth: 380, idealWidth: 540)
                    timeline(for: selectedDate.wrappedValue)
                        .frame(minWidth: 280, idealWidth: 360, maxWidth: 640)
                }
            }
        }
        .toolbar { toolbar(selectedDate: selectedDate) }
    }

    @ViewBuilder
    private var centerPane: some View {
        switch destination {
        case .focus, .timeline:
            FocusPaneView(
                onStart: { isStartingSession = true },
                onFinish: { reflecting = model.finishSession() }
            )
        case .day:
            DayReviewView(day: model.selectedDate)
        case .insights:
            InsightsView(anchor: model.selectedDate)
        case .settings:
            SettingsPaneView()
        case .categories:
            CategoryBreakdownView(day: model.selectedDate)
        }
    }

    private func timeline(for day: Date) -> some View {
        DayTimelineView(
            day: day,
            hourHeight: Binding(get: { CGFloat(hourHeight) }, set: { hourHeight = Double($0) })
        )
    }

    @ToolbarContentBuilder
    private func toolbar(selectedDate: Binding<Date>) -> some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { shift(selectedDate, by: -1) } label: {
                Image(systemName: "chevron.left")
            }
            .help("Previous day")

            Button { shift(selectedDate, by: 1) } label: {
                Image(systemName: "chevron.right")
            }
            .help("Next day")
            .disabled(Calendar.current.isDateInToday(selectedDate.wrappedValue))

            DateNavigator(date: selectedDate)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                ForEach([40.0, 60.0, 90.0, 140.0], id: \.self) { height in
                    Button {
                        hourHeight = height
                    } label: {
                        Label(zoomLabel(height), systemImage: hourHeight == height ? "checkmark" : "")
                    }
                }
            } label: {
                Image(systemName: "arrow.up.and.down.text.horizontal")
            }
            .help("Timeline zoom")

            Button {
                model.addBlock(on: model.selectedDate)
            } label: {
                Label("Add Block", systemImage: "plus")
            }
            .help("Add a time block")
            .keyboardShortcut("b", modifiers: .command)

            Button {
                if model.activeSession == nil { isStartingSession = true }
            } label: {
                Label("Start Session", systemImage: "play.fill")
            }
            .disabled(model.activeSession != nil)
            .help("Start a focus session")
        }
    }

    private func zoomLabel(_ height: Double) -> String {
        switch height {
        case ..<50: "Compact"
        case ..<70: "Default"
        case ..<100: "Comfortable"
        default: "Expanded"
        }
    }

    private func shift(_ date: Binding<Date>, by days: Int) {
        let calendar = Calendar.current
        guard let moved = calendar.date(byAdding: .day, value: days, to: date.wrappedValue) else { return }
        // Never navigate into the future; there is nothing recorded there.
        let today = calendar.startOfDay(for: .now)
        date.wrappedValue = min(calendar.startOfDay(for: moved), today)
    }
}
