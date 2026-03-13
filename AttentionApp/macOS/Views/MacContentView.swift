import SwiftUI
import SwiftData

struct MacContentView: View {
    @Environment(TodoListViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        @Bindable var vm = viewModel

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: AttentionLayout.sidebarWidth, max: 300)
        } content: {
            TodoListView()
                .navigationSplitViewColumnWidth(min: AttentionLayout.listMinWidth, ideal: 400, max: 600)
        } detail: {
            if let todo = viewModel.selectedTodo {
                TodoDetailView(todo: todo)
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "checklist",
                    description: Text("Select a todo to view its details")
                )
            }
        }
        .onAppear {
            viewModel.setup(modelContext: modelContext)
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(TodoListViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        List(selection: $vm.selectedSidebarItem) {
            // Smart Lists
            Section {
                sidebarRow(.inbox)
                sidebarRow(.today)
                sidebarRow(.upcoming)
                sidebarRow(.anytime)
                sidebarRow(.someday)
            }

            // Projects & Areas
            Section("Projects") {
                ForEach(viewModel.projects) { project in
                    sidebarRow(.project(project))
                }

                Button {
                    viewModel.createProject(title: "New Project")
                } label: {
                    Label("Add Project", systemImage: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Bottom
            Section {
                sidebarRow(.logbook)
                sidebarRow(.trash)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Attention")
        .onChange(of: viewModel.selectedSidebarItem) {
            viewModel.loadTodosForCurrentView()
        }
    }

    @ViewBuilder
    private func sidebarRow(_ item: SidebarItem) -> some View {
        Label {
            HStack {
                Text(item.title)
                Spacer()
                let count = viewModel.count(for: item)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } icon: {
            Image(systemName: item.systemImage)
                .foregroundStyle(item.accentColor)
                .symbolRenderingMode(.hierarchical)
        }
        .tag(item)
    }
}

// MARK: - Todo List

struct TodoListView: View {
    @Environment(TodoListViewModel.self) private var viewModel
    @State private var newTodoTitle = ""
    @FocusState private var isNewTodoFocused: Bool

    var body: some View {
        @Bindable var vm = viewModel

        List(selection: $vm.selectedTodo) {
            // New Todo Inline
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.attentionPrimary)
                    .font(.system(size: AttentionLayout.iconSize))

                TextField("New To-Do", text: $newTodoTitle)
                    .textFieldStyle(.plain)
                    .focused($isNewTodoFocused)
                    .onSubmit {
                        viewModel.createTodo(title: newTodoTitle)
                        newTodoTitle = ""
                    }
            }
            .padding(.vertical, AttentionLayout.tinyPadding)

            // Todo Items
            ForEach(viewModel.todos) { todo in
                TodoRowView(todo: todo)
                    .tag(todo)
            }
        }
        .listStyle(.inset)
        .navigationTitle(viewModel.selectedSidebarItem?.title ?? "Attention")
        .searchable(text: $vm.searchQuery, prompt: "Search")
        .onChange(of: viewModel.searchQuery) {
            viewModel.loadTodosForCurrentView()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isNewTodoFocused = true
                } label: {
                    Image(systemName: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

// MARK: - Todo Row

struct TodoRowView: View {
    let todo: Todo
    @Environment(TodoListViewModel.self) private var viewModel
    @State private var isCompleting = false

    var body: some View {
        HStack(spacing: 10) {
            // Checkbox
            Button {
                withAnimation(AttentionAnimation.springSnappy) {
                    isCompleting = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + AttentionAnimation.completionDelay) {
                    withAnimation(AttentionAnimation.springDefault) {
                        viewModel.completeTodo(todo)
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(checkboxColor, lineWidth: 1.5)
                        .frame(width: AttentionLayout.checkboxSize, height: AttentionLayout.checkboxSize)

                    if isCompleting {
                        Circle()
                            .fill(checkboxColor)
                            .frame(width: AttentionLayout.checkboxSize, height: AttentionLayout.checkboxSize)
                            .transition(.scale.combined(with: .opacity))

                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .transition(.scale)
                    }
                }
            }
            .buttonStyle(.plain)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .lineLimit(1)
                    .strikethrough(isCompleting, color: .secondary)
                    .foregroundStyle(isCompleting ? .secondary : .primary)

                HStack(spacing: 6) {
                    if let date = todo.scheduledDate {
                        Label(date.formatted(.dateTime.month(.abbreviated).day()), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(todo.isOverdue ? Color.attentionDanger : .secondary)
                    }

                    if !todo.tags.isEmpty {
                        ForEach(todo.tags.prefix(3)) { tag in
                            Text(tag.title)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(hex: tag.color).opacity(0.15))
                                .foregroundStyle(Color(hex: tag.color))
                                .clipShape(Capsule())
                        }
                    }

                    if !todo.checklist.isEmpty {
                        let completed = todo.checklist.filter(\.isCompleted).count
                        Label("\(completed)/\(todo.checklist.count)", systemImage: "checklist")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !todo.notes.isEmpty {
                        Image(systemName: "note.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Priority indicator
            if todo.priority != .none {
                Circle()
                    .fill(priorityColor)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                viewModel.deleteTodo(todo)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                viewModel.moveTodoToToday(todo)
            } label: {
                Label("Today", systemImage: "star")
            }
            .tint(.sidebarToday)
        }
    }

    private var checkboxColor: Color {
        switch todo.priority {
        case .none: .secondary.opacity(0.5)
        case .low: .blue
        case .medium: .orange
        case .high: Color.attentionDanger
        }
    }

    private var priorityColor: Color {
        switch todo.priority {
        case .none: .clear
        case .low: .blue
        case .medium: .orange
        case .high: Color.attentionDanger
        }
    }
}

// MARK: - Todo Detail

struct TodoDetailView: View {
    let todo: Todo
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var isEditing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                TextField("Title", text: $title)
                    .font(.title2.bold())
                    .textFieldStyle(.plain)
                    .onSubmit { todo.title = title; todo.markDirty() }

                Divider()

                // Metadata
                HStack(spacing: 20) {
                    if let date = todo.scheduledDate {
                        Label(date.formatted(.dateTime.weekday(.wide).month().day()), systemImage: "calendar")
                            .foregroundStyle(.secondary)
                    }

                    if let deadline = todo.deadline {
                        Label("Due: \(deadline.formatted(.dateTime.month().day()))", systemImage: "flag")
                            .foregroundStyle(todo.isOverdue ? Color.attentionDanger : .secondary)
                    }

                    if todo.priority != .none {
                        Label(todo.priority.label, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(priorityTextColor)
                    }
                }
                .font(.subheadline)

                // Tags
                if !todo.tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(todo.tags) { tag in
                            Text(tag.title)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(hex: tag.color).opacity(0.15))
                                .foregroundStyle(Color(hex: tag.color))
                                .clipShape(Capsule())
                        }
                    }
                }

                Divider()

                // Notes (Markdown)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $notes)
                        .font(.body)
                        .frame(minHeight: 200)
                        .scrollContentBackground(.hidden)
                        .onChange(of: notes) {
                            todo.notes = notes
                            todo.markDirty()
                        }
                }

                // Checklist
                if !todo.checklist.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Checklist")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        ForEach(todo.checklist.sorted(by: { $0.sortOrder < $1.sortOrder })) { item in
                            HStack(spacing: 8) {
                                Toggle(isOn: Binding(
                                    get: { item.isCompleted },
                                    set: { _ in item.toggle() }
                                )) {
                                    Text(item.title)
                                        .strikethrough(item.isCompleted)
                                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                }
                                .toggleStyle(AttentionCheckboxStyle())
                            }
                        }
                    }
                }
            }
            .padding(AttentionLayout.padding)
        }
        .onAppear {
            title = todo.title
            notes = todo.notes
        }
        .onChange(of: todo) {
            title = todo.title
            notes = todo.notes
        }
    }

    private var priorityTextColor: Color {
        switch todo.priority {
        case .none: .secondary
        case .low: .blue
        case .medium: .orange
        case .high: Color.attentionDanger
        }
    }
}

// MARK: - Flow Layout (for tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

#Preview {
    MacContentView()
        .environment(TodoListViewModel())
        .modelContainer(DataContainer.preview)
        .frame(width: 1000, height: 600)
}
