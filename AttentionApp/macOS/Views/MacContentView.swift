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
        .sheet(isPresented: $vm.showQuickEntry) {
            QuickEntryView()
                .environment(viewModel)
        }
        .onAppear {
            viewModel.setup(modelContext: modelContext)
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(TodoListViewModel.self) private var viewModel
    @State private var isAddingProject = false
    @State private var newProjectTitle = ""
    @State private var isAddingArea = false
    @State private var newAreaTitle = ""

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

            // Areas with nested projects
            if !viewModel.areas.isEmpty {
                ForEach(viewModel.areas) { area in
                    Section {
                        DisclosureGroup {
                            let areaProjects = viewModel.projects.filter { $0.area?.id == area.id }
                            ForEach(areaProjects) { project in
                                sidebarRow(.project(project))
                            }
                        } label: {
                            Label {
                                Text(area.title)
                                    .fontWeight(.medium)
                            } icon: {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.purple)
                            }
                        }
                    }
                }
            }

            // Standalone Projects (no area)
            Section {
                let standaloneProjects = viewModel.projects.filter { $0.area == nil }
                ForEach(standaloneProjects) { project in
                    sidebarRow(.project(project))
                }

                if isAddingProject {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet")
                            .foregroundStyle(Color.attentionPrimary)
                        TextField("Project Name", text: $newProjectTitle)
                            .textFieldStyle(.plain)
                            .onSubmit {
                                if !newProjectTitle.isEmpty {
                                    viewModel.createProject(title: newProjectTitle)
                                }
                                newProjectTitle = ""
                                isAddingProject = false
                            }
                            .onExitCommand {
                                newProjectTitle = ""
                                isAddingProject = false
                            }
                    }
                }

                Button {
                    isAddingProject = true
                } label: {
                    Label("Add Project", systemImage: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } header: {
                Text("Projects")
            }

            // Tags
            if !viewModel.tags.isEmpty {
                Section("Tags") {
                    ForEach(viewModel.tags) { tag in
                        sidebarRow(.tag(tag))
                    }
                }
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
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(.quaternary)
                        )
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
                        if !newTodoTitle.isEmpty {
                            withAnimation(AttentionAnimation.springDefault) {
                                viewModel.createTodo(title: newTodoTitle)
                            }
                            newTodoTitle = ""
                        }
                    }
            }
            .padding(.vertical, AttentionLayout.tinyPadding)

            // Todo Items
            ForEach(viewModel.todos) { todo in
                TodoRowView(todo: todo)
                    .tag(todo)
                    .contextMenu {
                        todoContextMenu(for: todo)
                    }
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

            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.showQuickEntry = true
                } label: {
                    Image(systemName: "bolt.fill")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
        .onDeleteCommand {
            if let todo = viewModel.selectedTodo {
                withAnimation(AttentionAnimation.springDefault) {
                    viewModel.deleteTodo(todo)
                }
            }
        }
    }

    @ViewBuilder
    private func todoContextMenu(for todo: Todo) -> some View {
        Button {
            viewModel.moveTodoToToday(todo)
        } label: {
            Label("Move to Today", systemImage: "star")
        }

        Menu("Schedule") {
            Button("Today") {
                viewModel.moveTodoToToday(todo)
            }
            Button("Tomorrow") {
                if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) {
                    viewModel.scheduleFor(todo, date: tomorrow)
                }
            }
            Button("Next Week") {
                if let nextWeek = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date()) {
                    viewModel.scheduleFor(todo, date: nextWeek)
                }
            }
        }

        Menu("Priority") {
            ForEach(Priority.allCases, id: \.rawValue) { priority in
                Button {
                    viewModel.setPriority(todo, priority: priority)
                } label: {
                    HStack {
                        Text(priority.label)
                        if todo.priority == priority {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        if !viewModel.projects.isEmpty {
            Menu("Move to Project") {
                Button("None") {
                    viewModel.moveToProject(todo, project: nil)
                }
                Divider()
                ForEach(viewModel.projects) { project in
                    Button(project.title) {
                        viewModel.moveToProject(todo, project: project)
                    }
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            withAnimation(AttentionAnimation.springDefault) {
                viewModel.deleteTodo(todo)
            }
        } label: {
            Label("Delete", systemImage: "trash")
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
                        isCompleting = false
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
                    if let project = todo.project {
                        Label(project.title, systemImage: "list.bullet")
                            .font(.caption)
                            .foregroundStyle(Color.attentionPrimary)
                    }

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
        .opacity(isCompleting ? 0.5 : 1.0)
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
    @Environment(TodoListViewModel.self) private var viewModel
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var scheduledDate: Date = Date()
    @State private var hasScheduledDate: Bool = false
    @State private var deadlineDate: Date = Date()
    @State private var hasDeadline: Bool = false
    @State private var selectedPriority: Priority = .none
    @State private var newChecklistTitle: String = ""
    @State private var showTagPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title
                TextField("Title", text: $title)
                    .font(.title2.bold())
                    .textFieldStyle(.plain)
                    .onSubmit { applyTitle() }
                    .onChange(of: title) { applyTitle() }

                Divider()

                // Scheduling Section
                detailSection("Schedule") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Scheduled Date
                        HStack {
                            Toggle(isOn: $hasScheduledDate) {
                                Label("When", systemImage: "calendar")
                                    .foregroundStyle(.secondary)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }

                        if hasScheduledDate {
                            DatePicker(
                                "Scheduled Date",
                                selection: $scheduledDate,
                                displayedComponents: [.date]
                            )
                            .labelsHidden()
                            .onChange(of: scheduledDate) {
                                todo.scheduleFor(scheduledDate)
                                viewModel.saveTodo()
                            }
                        }

                        // Deadline
                        HStack {
                            Toggle(isOn: $hasDeadline) {
                                Label("Deadline", systemImage: "flag")
                                    .foregroundStyle(.secondary)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }

                        if hasDeadline {
                            DatePicker(
                                "Deadline",
                                selection: $deadlineDate,
                                displayedComponents: [.date]
                            )
                            .labelsHidden()
                            .onChange(of: deadlineDate) {
                                todo.deadline = deadlineDate
                                todo.markDirty()
                                viewModel.saveTodo()
                            }
                        }
                    }
                }

                // Priority
                detailSection("Priority") {
                    Picker("Priority", selection: $selectedPriority) {
                        ForEach(Priority.allCases, id: \.rawValue) { priority in
                            Text(priority.label).tag(priority)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedPriority) {
                        viewModel.setPriority(todo, priority: selectedPriority)
                    }
                }

                // Project Assignment
                detailSection("Project") {
                    Picker("Project", selection: Binding(
                        get: { todo.project },
                        set: { newProject in
                            viewModel.moveToProject(todo, project: newProject)
                        }
                    )) {
                        Text("None").tag(nil as Project?)
                        ForEach(viewModel.projects) { project in
                            Text(project.title).tag(project as Project?)
                        }
                    }
                    .labelsHidden()
                }

                // Tags
                detailSection("Tags") {
                    VStack(alignment: .leading, spacing: 8) {
                        FlowLayout(spacing: 6) {
                            ForEach(viewModel.tags) { tag in
                                let isSelected = todo.tags.contains(where: { $0.id == tag.id })
                                Button {
                                    withAnimation(AttentionAnimation.springSnappy) {
                                        viewModel.toggleTag(tag, on: todo)
                                    }
                                } label: {
                                    Text(tag.title)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            isSelected
                                                ? Color(hex: tag.color).opacity(0.2)
                                                : Color.clear
                                        )
                                        .foregroundStyle(
                                            isSelected
                                                ? Color(hex: tag.color)
                                                : .secondary
                                        )
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(
                                                    isSelected
                                                        ? Color(hex: tag.color).opacity(0.5)
                                                        : Color.secondary.opacity(0.3),
                                                    lineWidth: 1
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if viewModel.tags.isEmpty {
                            Text("No tags available")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Divider()

                // Notes (Markdown)
                detailSection("Notes") {
                    MarkdownEditorView(text: $notes)
                        .onChange(of: notes) {
                            todo.notes = notes
                            todo.markDirty()
                            viewModel.saveTodo()
                        }
                }

                // Checklist
                detailSection("Checklist") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(todo.checklist.sorted(by: { $0.sortOrder < $1.sortOrder })) { item in
                            HStack(spacing: 8) {
                                Toggle(isOn: Binding(
                                    get: { item.isCompleted },
                                    set: { _ in
                                        withAnimation(AttentionAnimation.springSnappy) {
                                            item.toggle()
                                            viewModel.saveTodo()
                                        }
                                    }
                                )) {
                                    Text(item.title)
                                        .strikethrough(item.isCompleted)
                                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                }
                                .toggleStyle(AttentionCheckboxStyle())

                                Spacer()

                                Button {
                                    withAnimation(AttentionAnimation.springDefault) {
                                        viewModel.removeChecklistItem(item, from: todo)
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.tertiary)
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Add checklist item
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 14))

                            TextField("Add item", text: $newChecklistTitle)
                                .textFieldStyle(.plain)
                                .font(.callout)
                                .onSubmit {
                                    if !newChecklistTitle.isEmpty {
                                        withAnimation(AttentionAnimation.springDefault) {
                                            viewModel.addChecklistItem(to: todo, title: newChecklistTitle)
                                            newChecklistTitle = ""
                                        }
                                    }
                                }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(AttentionLayout.padding)
        }
        .onAppear { syncFromTodo() }
        .onChange(of: todo) { syncFromTodo() }
    }

    private func syncFromTodo() {
        title = todo.title
        notes = todo.notes
        selectedPriority = todo.priority
        hasScheduledDate = todo.scheduledDate != nil
        scheduledDate = todo.scheduledDate ?? Date()
        hasDeadline = todo.deadline != nil
        deadlineDate = todo.deadline ?? Date()
    }

    private func applyTitle() {
        guard todo.title != title else { return }
        todo.title = title
        todo.markDirty()
        viewModel.saveTodo()
    }

    @ViewBuilder
    private func detailSection(_ header: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            content()
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
