import SwiftUI
import SwiftData

struct WatchContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Todo.sortOrder) private var allTodos: [Todo]

    private var todayTodos: [Todo] {
        allTodos.filter { ($0.status == .active || $0.status == .inbox) && $0.scheduledDate != nil }
    }

    var body: some View {
        NavigationStack {
            if todayTodos.isEmpty {
                ContentUnavailableView(
                    "All Done!",
                    systemImage: "checkmark.circle",
                    description: Text("No tasks for today")
                )
            } else {
                List {
                    ForEach(todayTodos) { todo in
                        WatchTodoRow(todo: todo)
                    }
                }
                .navigationTitle("Today")
            }
        }
    }
}

struct WatchTodoRow: View {
    let todo: Todo
    @State private var isCompleted = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isCompleted = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                todo.complete()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isCompleted ? .green : .secondary)
                    .symbolEffect(.bounce, value: isCompleted)

                VStack(alignment: .leading, spacing: 2) {
                    Text(todo.title)
                        .lineLimit(2)
                        .font(.body)
                        .strikethrough(isCompleted)

                    if let deadline = todo.deadline {
                        Text(deadline.formatted(.dateTime.hour().minute()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: isCompleted)
    }
}
