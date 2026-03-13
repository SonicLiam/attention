import SwiftUI
import SwiftData

struct iOSContentView: View {
    @Environment(TodoListViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: SidebarItem = .inbox

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Inbox", systemImage: "tray", value: .inbox) {
                iOSTodoListView(sidebarItem: .inbox)
            }

            Tab("Today", systemImage: "star", value: .today) {
                iOSTodoListView(sidebarItem: .today)
            }

            Tab("Upcoming", systemImage: "calendar", value: .upcoming) {
                iOSTodoListView(sidebarItem: .upcoming)
            }

            Tab("Anytime", systemImage: "square.stack", value: .anytime) {
                iOSTodoListView(sidebarItem: .anytime)
            }

            Tab("Projects", systemImage: "list.bullet", value: .logbook) {
                iOSProjectsView()
            }
        }
        .tint(Color.attentionPrimary)
        .onAppear {
            viewModel.setup(modelContext: modelContext)
        }
    }
}

// MARK: - iOS Todo List

struct iOSTodoListView: View {
    let sidebarItem: SidebarItem
    @Environment(TodoListViewModel.self) private var viewModel
    @State private var showNewTodo = false
    @State private var newTodoTitle = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.todos) { todo in
                    NavigationLink(value: todo) {
                        iOSTodoRowView(todo: todo)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            withAnimation(AttentionAnimation.springSnappy) {
                                viewModel.completeTodo(todo)
                            }
                        } label: {
                            Label("Done", systemImage: "checkmark")
                        }
                        .tint(Color.attentionSuccess)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            viewModel.moveTodoToToday(todo)
                        } label: {
                            Label("Today", systemImage: "star")
                        }
                        .tint(.sidebarToday)

                        Button(role: .destructive) {
                            viewModel.deleteTodo(todo)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(sidebarItem.title)
            .navigationDestination(for: Todo.self) { todo in
                iOSTodoDetailView(todo: todo)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showNewTodo = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showNewTodo) {
                NavigationStack {
                    Form {
                        TextField("New To-Do", text: $newTodoTitle)
                    }
                    .navigationTitle("New To-Do")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showNewTodo = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                viewModel.createTodo(title: newTodoTitle)
                                newTodoTitle = ""
                                showNewTodo = false
                            }
                            .disabled(newTodoTitle.isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .onAppear {
                viewModel.selectedSidebarItem = sidebarItem
                viewModel.loadTodosForCurrentView()
            }
        }
    }
}

// MARK: - iOS Todo Row

struct iOSTodoRowView: View {
    let todo: Todo

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .strokeBorder(checkboxColor, lineWidth: 1.5)
                .frame(width: AttentionLayout.checkboxSize, height: AttentionLayout.checkboxSize)

            VStack(alignment: .leading, spacing: 3) {
                Text(todo.title)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let date = todo.scheduledDate {
                        Text(date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.caption)
                            .foregroundStyle(todo.isOverdue ? Color.attentionDanger : .secondary)
                    }

                    if !todo.tags.isEmpty {
                        Text(todo.tags.map(\.title).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(Color.attentionPrimary)
                    }
                }
            }

            Spacer()

            if todo.priority != .none {
                Circle()
                    .fill(priorityColor)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 2)
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

// MARK: - iOS Todo Detail

struct iOSTodoDetailView: View {
    let todo: Todo
    @State private var title: String = ""
    @State private var notes: String = ""

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title)
                    .font(.headline)
                    .onChange(of: title) { todo.title = title; todo.markDirty() }
            }

            Section("Schedule") {
                if let date = todo.scheduledDate {
                    LabeledContent("Date", value: date.formatted(.dateTime.weekday(.wide).month().day()))
                }
                if let deadline = todo.deadline {
                    LabeledContent("Deadline", value: deadline.formatted(.dateTime.month().day()))
                }
                LabeledContent("Priority", value: todo.priority.label)
            }

            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 150)
                    .onChange(of: notes) { todo.notes = notes; todo.markDirty() }
            }

            if !todo.checklist.isEmpty {
                Section("Checklist") {
                    ForEach(todo.checklist.sorted(by: { $0.sortOrder < $1.sortOrder })) { item in
                        HStack {
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isCompleted ? Color.attentionSuccess : .secondary)
                                .onTapGesture { item.toggle() }
                            Text(item.title)
                                .strikethrough(item.isCompleted)
                        }
                    }
                }
            }

            if !todo.tags.isEmpty {
                Section("Tags") {
                    ForEach(todo.tags) { tag in
                        Label(tag.title, systemImage: "tag")
                            .foregroundStyle(Color(hex: tag.color))
                    }
                }
            }
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            title = todo.title
            notes = todo.notes
        }
    }
}

// MARK: - iOS Projects View

struct iOSProjectsView: View {
    @Environment(TodoListViewModel.self) private var viewModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.projects) { project in
                    NavigationLink(value: project) {
                        HStack {
                            Image(systemName: "list.bullet")
                                .foregroundStyle(Color.attentionPrimary)

                            VStack(alignment: .leading) {
                                Text(project.title)
                                    .font(.headline)

                                if project.totalTodos > 0 {
                                    Text("\(project.completedTodos)/\(project.totalTodos) completed")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if project.totalTodos > 0 {
                                CircularProgressView(progress: project.progress)
                                    .frame(width: 28, height: 28)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Projects")
            .navigationDestination(for: Project.self) { project in
                iOSTodoListView(sidebarItem: .project(project))
            }
        }
    }
}

// MARK: - Circular Progress

struct CircularProgressView: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 3)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.attentionPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(AttentionAnimation.springDefault, value: progress)
        }
    }
}

#Preview {
    iOSContentView()
        .environment(TodoListViewModel())
        .modelContainer(DataContainer.preview)
}
