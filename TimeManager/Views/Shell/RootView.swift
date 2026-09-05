import SwiftData
import SwiftUI

enum Destination: String, Hashable, CaseIterable, Identifiable {
    case focus, timeline, day, insights, categories, guide, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: "Focus"
        case .timeline: "Timeline"
        case .day: "Day"
        case .insights: "Insights"
        case .guide: "Guide"
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
        case .guide: "book"
        case .settings: "gearshape"
        case .categories: "circle.grid.3x3"
        }
    }
}

struct RootView: View {

    @Environment(AppModel.self) private var model

    @AppStorage("hasSeenGuide") private var hasSeenGuide = false
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var isOnboarding = false
    @State private var destination: Destination = .focus

    private static let sidebarWidth: CGFloat = 216
    private static let centreMinimum: CGFloat = 380
    private static let timelineMinimum: CGFloat = 300
    /// Deliberately more than the sum of the pane minimums: an exact fit leaves
    /// nothing for the divider and the panes overflow their slots.
    private static let minimumWidth: CGFloat = 216 + 380 + 300 + 80
    private static let minimumHeight: CGFloat = 620
    @State private var isStartingSession = false
    @State private var reflecting: WorkSession?
    @AppStorage("timeline.hourHeight") private var hourHeight: Double = 60

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SidebarView(selection: $destination)
                    .frame(width: Self.sidebarWidth)
                Divider()
                detail(selectedDate: $model.selectedDate)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            StatusBarView()
        }
        // Deliberately more than the sum of the pane minimums: an exact fit
        // leaves nothing for the divider and the panes overflow their slots.
        .frame(minWidth: Self.minimumWidth, minHeight: Self.minimumHeight)
        .background(WindowMinimumSize(width: Self.minimumWidth, height: Self.minimumHeight))
        .task {
            guard !hasOnboarded else { return }
            isOnboarding = true
        }
        .sheet(isPresented: $isOnboarding) {
            OnboardingView { openGuide in
                hasOnboarded = true
                hasSeenGuide = true
                isOnboarding = false
                if openGuide { destination = .guide }
            }
            .environment(model)
            .interactiveDismissDisabled()
        }
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
                        .frame(minWidth: Self.centreMinimum, idealWidth: 540)
                    timeline(for: selectedDate.wrappedValue)
                        .frame(minWidth: Self.timelineMinimum, idealWidth: 360, maxWidth: 640)
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
        case .guide:
            GuideView()
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
            .accessibilityIdentifier("toolbar.previousDay")
            .keyboardShortcut("[", modifiers: .command)

            Button { shift(selectedDate, by: 1) } label: {
                Image(systemName: "chevron.right")
            }
            .help("Next day")
            .accessibilityIdentifier("toolbar.nextDay")
            .keyboardShortcut("]", modifiers: .command)
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
                    .accessibilityIdentifier("zoom.\(zoomLabel(height))")
                }
            } label: {
                Image(systemName: "arrow.up.and.down.text.horizontal")
            }
            .help("Timeline zoom")
            .accessibilityIdentifier("toolbar.zoom")

            Button {
                model.addBlock(on: model.selectedDate)
            } label: {
                Label("Add Block", systemImage: "plus")
            }
            .help("Add a time block")
            .accessibilityIdentifier("toolbar.addBlock")
            .keyboardShortcut("b", modifiers: .command)

            Button {
                if model.activeSession == nil { isStartingSession = true }
            } label: {
                Label("Start Session", systemImage: "play.fill")
            }
            .disabled(model.activeSession != nil)
            .accessibilityIdentifier("toolbar.startSession")
            .keyboardShortcut("n", modifiers: .command)
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
