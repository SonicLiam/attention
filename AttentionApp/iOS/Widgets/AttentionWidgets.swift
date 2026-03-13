import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

// MARK: - Widget Bundle

@main
struct AttentionWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayOverviewWidget()
        TodayListWidget()
        QuickAddWidget()
    }
}

// MARK: - Toggle Todo Intent (iOS 17+ Interactive Widget)

struct ToggleTodoIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle To-Do"
    static let description: IntentDescription = "Mark a to-do as complete or incomplete"

    @Parameter(title: "Todo ID")
    var todoId: String

    init() {}

    init(todoId: String) {
        self.todoId = todoId
    }

    func perform() async throws -> some IntentResult {
        // In a real implementation, this would toggle the todo in the shared data store
        return .result()
    }
}

// MARK: - Today Overview Widget (Small)

struct TodayOverviewProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayOverviewEntry {
        TodayOverviewEntry(date: Date(), totalCount: 5, completedCount: 2)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayOverviewEntry) -> Void) {
        completion(TodayOverviewEntry(date: Date(), totalCount: 5, completedCount: 2))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayOverviewEntry>) -> Void) {
        let entry = TodayOverviewEntry(date: Date(), totalCount: 0, completedCount: 0)
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900)))
        completion(timeline)
    }
}

struct TodayOverviewEntry: TimelineEntry {
    let date: Date
    let totalCount: Int
    let completedCount: Int

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    var remaining: Int { totalCount - completedCount }
}

struct TodayOverviewWidget: Widget {
    let kind = "TodayOverview"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayOverviewProvider()) { entry in
            TodayOverviewWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today Overview")
        .description("See your progress for today at a glance.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct TodayOverviewWidgetView: View {
    let entry: TodayOverviewEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                Text("Today")
                    .font(.headline)
                Spacer()
                Text(entry.date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: entry.progress)
                    .stroke(
                        Color.attentionPrimary,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(entry.remaining)")
                        .font(.title.bold())
                        .monospacedDigit()
                    Text("left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var circularView: some View {
        Gauge(value: entry.progress) {
            Text("\(entry.remaining)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var rectangularView: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Today")
                    .font(.headline)
                Text("\(entry.remaining) remaining")
                    .font(.caption)
            }
            Spacer()
            Gauge(value: entry.progress) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .frame(width: 50)
        }
    }
}

// MARK: - Today List Widget (Medium/Large)

struct TodayListProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayListEntry {
        TodayListEntry(date: Date(), todos: [
            WidgetTodo(title: "Review design specs", isCompleted: false, priority: .medium),
            WidgetTodo(title: "Team standup", isCompleted: true, priority: .none),
            WidgetTodo(title: "Write documentation", isCompleted: false, priority: .high),
            WidgetTodo(title: "Code review", isCompleted: false, priority: .low),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayListEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayListEntry>) -> Void) {
        let entry = TodayListEntry(date: Date(), todos: [])
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900)))
        completion(timeline)
    }
}

struct WidgetTodo: Identifiable {
    let id = UUID()
    let title: String
    let isCompleted: Bool
    let priority: Priority

    init(title: String, isCompleted: Bool, priority: Priority = .none) {
        self.title = title
        self.isCompleted = isCompleted
        self.priority = priority
    }
}

struct TodayListEntry: TimelineEntry {
    let date: Date
    let todos: [WidgetTodo]

    var completedCount: Int { todos.filter(\.isCompleted).count }
    var totalCount: Int { todos.count }
}

struct TodayListWidget: Widget {
    let kind = "TodayList"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayListProvider()) { entry in
            TodayListWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today List")
        .description("See your today's to-dos with interactive toggles.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TodayListWidgetView: View {
    let entry: TodayListEntry

    @Environment(\.widgetFamily) var family

    var maxItems: Int {
        family == .systemLarge ? 8 : 4
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack(alignment: .center) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                Text("Today")
                    .font(.headline)
                Spacer()
                if entry.totalCount > 0 {
                    Text("\(entry.completedCount)/\(entry.totalCount)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.bottom, 2)

            if entry.todos.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title2)
                            .foregroundStyle(Color.attentionSuccess)
                        Text("All done for today!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(Array(entry.todos.prefix(maxItems).enumerated()), id: \.element.id) { index, todo in
                    if index > 0 {
                        Divider()
                    }
                    widgetTodoRow(todo)
                }

                if entry.todos.count > maxItems {
                    Text("+\(entry.todos.count - maxItems) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func widgetTodoRow(_ todo: WidgetTodo) -> some View {
        HStack(spacing: 8) {
            // Interactive toggle button (iOS 17+)
            Button(intent: ToggleTodoIntent(todoId: todo.id.uuidString)) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(todo.isCompleted ? Color.attentionSuccess : priorityColor(todo.priority))
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)

            Text(todo.title)
                .font(.subheadline)
                .lineLimit(1)
                .strikethrough(todo.isCompleted)
                .foregroundStyle(todo.isCompleted ? .secondary : .primary)

            Spacer()

            if !todo.isCompleted && todo.priority != .none {
                Circle()
                    .fill(priorityColor(todo.priority))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.vertical, 1)
    }

    private func priorityColor(_ priority: Priority) -> Color {
        switch priority {
        case .none: .secondary
        case .low: .blue
        case .medium: .orange
        case .high: Color.attentionDanger
        }
    }
}

// MARK: - Quick Add Widget (Small)

struct QuickAddProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickAddEntry {
        QuickAddEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickAddEntry) -> Void) {
        completion(QuickAddEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickAddEntry>) -> Void) {
        let timeline = Timeline(entries: [QuickAddEntry(date: Date())], policy: .never)
        completion(timeline)
    }
}

struct QuickAddEntry: TimelineEntry {
    let date: Date
}

struct QuickAddWidget: Widget {
    let kind = "QuickAdd"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickAddProvider()) { _ in
            QuickAddWidgetView()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Add")
        .description("Quickly add a new to-do.")
        .supportedFamilies([.systemSmall])
    }
}

struct QuickAddWidgetView: View {
    var body: some View {
        Link(destination: URL(string: "attention://new")!) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.attentionPrimary, Color.attentionSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)

                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Text("New To-Do")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
        }
    }
}
