import SwiftUI
import SwiftData

struct iOSContentView: View {
    @Environment(TodoListViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: SidebarItem = .inbox

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Inbox", systemImage: "tray.fill", value: .inbox) {
                iOSTodoListView(sidebarItem: .inbox)
            }

            Tab("Today", systemImage: "star.fill", value: .today) {
                iOSTodoListView(sidebarItem: .today)
            }

            Tab("Upcoming", systemImage: "calendar", value: .upcoming) {
                iOSTodoListView(sidebarItem: .upcoming)
            }

            Tab("Projects", systemImage: "list.bullet.clipboard", value: .anytime) {
                iOSProjectsView()
            }

            Tab("Browse", systemImage: "square.grid.2x2", value: .logbook) {
                iOSBrowseView()
            }
        }
        .tint(Color.attentionPrimary)
        .onAppear {
            viewModel.setup(modelContext: modelContext)
        }
    }
}

// MARK: - Browse View (Someday / Logbook / Anytime)

struct iOSBrowseView: View {
    @Environment(TodoListViewModel.self) private var viewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        iOSTodoListView(sidebarItem: .anytime)
                    } label: {
                        Label {
                            Text("Anytime")
                        } icon: {
                            Image(systemName: "square.stack.fill")
                                .foregroundStyle(Color.sidebarAnytime)
                        }
                    }

                    NavigationLink {
                        iOSTodoListView(sidebarItem: .someday)
                    } label: {
                        Label {
                            Text("Someday")
                        } icon: {
                            Image(systemName: "archivebox.fill")
                                .foregroundStyle(Color.sidebarSomeday)
                        }
                    }

                    NavigationLink {
                        iOSTodoListView(sidebarItem: .logbook)
                    } label: {
                        Label {
                            Text("Logbook")
                        } icon: {
                            Image(systemName: "book.fill")
                                .foregroundStyle(Color.sidebarLogbook)
                        }
                    }

                    NavigationLink {
                        iOSTodoListView(sidebarItem: .trash)
                    } label: {
                        Label {
                            Text("Trash")
                        } icon: {
                            Image(systemName: "trash.fill")
                                .foregroundStyle(.gray)
                        }
                    }
                }
            }
            .navigationTitle("Browse")
        }
    }
}

// MARK: - iOS Todo List

struct iOSTodoListView: View {
    let sidebarItem: SidebarItem
    @Environment(TodoListViewModel.self) private var viewModel
    @State private var showNewTodo = false
    @State private var newTodoTitle = ""
    @State private var showMagicPlusOptions = false
    @State private var fabScale: CGFloat = 1.0
    @State private var showSchedulePicker = false
    @State private var todoToSchedule: Todo?
    @State private var detectedDate: Date?
    @State private var detectedCleanTitle: String?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
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
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.success)
                            } label: {
                                Label("Done", systemImage: "checkmark")
                            }
                            .tint(Color.attentionSuccess)
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                todoToSchedule = todo
                                showSchedulePicker = true
                            } label: {
                                Label("Schedule", systemImage: "calendar")
                            }
                            .tint(Color.sidebarUpcoming)

                            Button {
                                viewModel.moveTodoToToday(todo)
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                            } label: {
                                Label("Today", systemImage: "star.fill")
                            }
                            .tint(Color.sidebarToday)

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
                .overlay {
                    if viewModel.todos.isEmpty {
                        ContentUnavailableView {
                            Label(emptyTitle, systemImage: emptyIcon)
                        } description: {
                            Text(emptyDescription)
                        }
                    }
                }

                // Magic Plus FAB
                magicPlusFAB
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
            }
            .sheet(isPresented: $showNewTodo) {
                newTodoSheet
            }
            .sheet(isPresented: $showSchedulePicker) {
                scheduleDatePicker
            }
            .confirmationDialog("New...", isPresented: $showMagicPlusOptions) {
                Button("New To-Do") {
                    showNewTodo = true
                }
                Button("New To-Do in Inbox") {
                    showNewTodo = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear {
                viewModel.selectedSidebarItem = sidebarItem
                viewModel.loadTodosForCurrentView()
            }
        }
    }

    // MARK: - Magic Plus FAB

    private var magicPlusFAB: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            showNewTodo = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(Color.attentionPrimary)
                        .shadow(color: Color.attentionPrimary.opacity(0.4), radius: 8, y: 4)
                )
        }
        .scaleEffect(fabScale)
        .onLongPressGesture(minimumDuration: 0.4) {
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
            showMagicPlusOptions = true
        } onPressingChanged: { pressing in
            withAnimation(AttentionAnimation.springSnappy) {
                fabScale = pressing ? 0.85 : 1.0
            }
        }
        .animation(AttentionAnimation.springBouncy, value: fabScale)
    }

    // MARK: - New Todo Sheet

    private var newTodoSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What do you want to do?", text: $newTodoTitle)
                        .font(.headline)
                        .onChange(of: newTodoTitle) {
                            if let result = NaturalDateParser.detectAndExtract(from: newTodoTitle) {
                                detectedDate = result.date
                                detectedCleanTitle = result.cleanedTitle
                            } else {
                                detectedDate = nil
                                detectedCleanTitle = nil
                            }
                        }
                }

                if let detected = detectedDate {
                    Section {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.attentionPrimary)
                            Text("Schedule for \(detected.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Apply") {
                                if let clean = detectedCleanTitle {
                                    newTodoTitle = clean
                                }
                                detectedDate = nil
                                detectedCleanTitle = nil
                            }
                            .font(.subheadline)
                            .foregroundStyle(Color.attentionPrimary)
                        }
                    }
                }
            }
            .navigationTitle("New To-Do")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        newTodoTitle = ""
                        detectedDate = nil
                        detectedCleanTitle = nil
                        showNewTodo = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let titleToUse = detectedCleanTitle ?? newTodoTitle
                        let dateToUse = detectedDate
                        if let dateToUse {
                            viewModel.createTodoWithDetails(title: titleToUse, scheduledDate: dateToUse)
                        } else {
                            viewModel.createTodo(title: titleToUse)
                        }
                        newTodoTitle = ""
                        detectedDate = nil
                        detectedCleanTitle = nil
                        showNewTodo = false
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    }
                    .fontWeight(.semibold)
                    .disabled(newTodoTitle.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Schedule Date Picker

    private var scheduleDatePicker: some View {
        NavigationStack {
            ScheduleDatePickerView(todo: todoToSchedule, viewModel: viewModel, isPresented: $showSchedulePicker)
        }
        .presentationDetents([.medium])
    }

    // MARK: - Empty State Helpers

    private var emptyTitle: String {
        switch sidebarItem {
        case .inbox: return "Inbox is Empty"
        case .today: return "Nothing for Today"
        case .upcoming: return "Nothing Upcoming"
        case .logbook: return "No Completed Tasks"
        default: return "No Tasks"
        }
    }

    private var emptyIcon: String {
        switch sidebarItem {
        case .inbox: return "tray"
        case .today: return "star"
        case .upcoming: return "calendar"
        case .logbook: return "book"
        default: return "checkmark.circle"
        }
    }

    private var emptyDescription: String {
        switch sidebarItem {
        case .inbox: return "Tap + to add a new to-do."
        case .today: return "Enjoy your day!"
        case .upcoming: return "Schedule tasks for the future."
        case .logbook: return "Completed tasks will appear here."
        default: return "Nothing here yet."
        }
    }
}

// MARK: - Schedule Date Picker View

struct ScheduleDatePickerView: View {
    let todo: Todo?
    let viewModel: TodoListViewModel
    @Binding var isPresented: Bool
    @State private var selectedDate = Date()

    var body: some View {
        Form {
            Section("Quick Options") {
                Button {
                    if let todo {
                        viewModel.moveTodoToToday(todo)
                    }
                    isPresented = false
                } label: {
                    Label("Today", systemImage: "star.fill")
                        .foregroundStyle(Color.sidebarToday)
                }

                Button {
                    if let todo {
                        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
                        viewModel.scheduleFor(todo, date: tomorrow)
                    }
                    isPresented = false
                } label: {
                    Label("Tomorrow", systemImage: "sunrise.fill")
                        .foregroundStyle(.orange)
                }

                Button {
                    if let todo {
                        todo.moveToSomeday()
                    }
                    isPresented = false
                } label: {
                    Label("Someday", systemImage: "archivebox.fill")
                        .foregroundStyle(Color.sidebarSomeday)
                }
            }

            Section("Pick a Date") {
                DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Color.attentionPrimary)

                Button("Schedule") {
                    if let todo {
                        viewModel.scheduleFor(todo, date: selectedDate)
                    }
                    isPresented = false
                }
                .fontWeight(.semibold)
                .foregroundStyle(Color.attentionPrimary)
            }
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { isPresented = false }
            }
        }
    }
}

// MARK: - iOS Todo Row

struct iOSTodoRowView: View {
    let todo: Todo
    @Environment(TodoListViewModel.self) private var viewModel
    @State private var checkboxAnimating = false

    var body: some View {
        HStack(spacing: 12) {
            // Tappable checkbox
            Button {
                withAnimation(AttentionAnimation.springSnappy) {
                    checkboxAnimating = true
                    viewModel.completeTodo(todo)
                }
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(checkboxColor, lineWidth: 1.5)
                        .frame(width: AttentionLayout.checkboxSize, height: AttentionLayout.checkboxSize)

                    if checkboxAnimating {
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

            VStack(alignment: .leading, spacing: 3) {
                Text(todo.title)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let date = todo.scheduledDate {
                        Label {
                            Text(date.formatted(.dateTime.month(.abbreviated).day()))
                        } icon: {
                            Image(systemName: "calendar")
                        }
                        .font(.caption)
                        .foregroundStyle(todo.isOverdue ? Color.attentionDanger : .secondary)
                    }

                    if let deadline = todo.deadline {
                        Label {
                            Text(deadline.formatted(.dateTime.month(.abbreviated).day()))
                        } icon: {
                            Image(systemName: "flag.fill")
                        }
                        .font(.caption)
                        .foregroundStyle(todo.isOverdue ? Color.attentionDanger : Color.attentionWarning)
                    }

                    if !todo.tags.isEmpty {
                        Text(todo.tags.map(\.title).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(Color.attentionPrimary)
                    }

                    if !todo.checklist.isEmpty {
                        let completed = todo.checklist.filter(\.isCompleted).count
                        Label {
                            Text("\(completed)/\(todo.checklist.count)")
                        } icon: {
                            Image(systemName: "checklist")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
    @Environment(TodoListViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var priority: Priority = .none
    @State private var scheduledDate: Date?
    @State private var hasScheduledDate = false
    @State private var deadline: Date?
    @State private var hasDeadline = false
    @State private var newChecklistTitle = ""
    @State private var hasChanges = false

    var body: some View {
        Form {
            // Title section
            Section {
                TextField("Title", text: $title)
                    .font(.headline)
                    .onChange(of: title) { hasChanges = true }
            }

            // Schedule section
            Section("Schedule") {
                Toggle("Scheduled Date", isOn: $hasScheduledDate.animation())
                if hasScheduledDate {
                    DatePicker(
                        "Date",
                        selection: Binding(
                            get: { scheduledDate ?? Date() },
                            set: { scheduledDate = $0; hasChanges = true }
                        ),
                        displayedComponents: [.date]
                    )
                    .tint(Color.attentionPrimary)
                }

                Toggle("Deadline", isOn: $hasDeadline.animation())
                if hasDeadline {
                    DatePicker(
                        "Deadline",
                        selection: Binding(
                            get: { deadline ?? Date() },
                            set: { deadline = $0; hasChanges = true }
                        ),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .tint(Color.attentionDanger)
                }
            }

            // Priority section
            Section("Priority") {
                Picker("Priority", selection: $priority) {
                    ForEach(Priority.allCases, id: \.self) { p in
                        Label {
                            Text(p.label)
                        } icon: {
                            Image(systemName: priorityIcon(for: p))
                                .foregroundStyle(priorityPickerColor(for: p))
                        }
                        .tag(p)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .onChange(of: priority) { hasChanges = true }
            }

            // Tags section
            if !todo.tags.isEmpty {
                Section("Tags") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(todo.tags) { tag in
                                Text(tag.title)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(Color(hex: tag.color).opacity(0.15))
                                    )
                                    .foregroundStyle(Color(hex: tag.color))
                            }
                        }
                    }
                }
            }

            // Checklist section
            Section("Checklist") {
                ForEach(todo.checklist.sorted(by: { $0.sortOrder < $1.sortOrder })) { item in
                    HStack {
                        Button {
                            withAnimation(AttentionAnimation.springSnappy) {
                                item.toggle()
                            }
                            let generator = UISelectionFeedbackGenerator()
                            generator.selectionChanged()
                        } label: {
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isCompleted ? Color.attentionSuccess : .secondary)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)

                        Text(item.title)
                            .strikethrough(item.isCompleted)
                            .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    }
                }

                HStack {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Color.attentionPrimary)
                    TextField("Add item", text: $newChecklistTitle)
                        .onSubmit {
                            addChecklistItem()
                        }
                }
            }

            // Project assignment
            if let project = todo.project {
                Section("Project") {
                    Label {
                        Text(project.title)
                    } icon: {
                        Image(systemName: "list.bullet.clipboard")
                            .foregroundStyle(Color.attentionPrimary)
                    }
                }
            }

            // Notes section
            Section("Notes") {
                MarkdownEditorView(text: $notes)
                    .onChange(of: notes) { hasChanges = true }
            }
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if hasChanges {
                    Button("Save") {
                        saveChanges()
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.attentionPrimary)
                }
            }
        }
        .onAppear {
            title = todo.title
            notes = todo.notes
            priority = todo.priority
            scheduledDate = todo.scheduledDate
            hasScheduledDate = todo.scheduledDate != nil
            deadline = todo.deadline
            hasDeadline = todo.deadline != nil
            hasChanges = false
        }
    }

    private func saveChanges() {
        todo.title = title
        todo.notes = notes
        todo.priority = priority
        todo.scheduledDate = hasScheduledDate ? (scheduledDate ?? Date()) : nil
        todo.deadline = hasDeadline ? (deadline ?? Date()) : nil
        todo.markDirty()
        hasChanges = false
    }

    private func addChecklistItem() {
        guard !newChecklistTitle.isEmpty else { return }
        let maxOrder = todo.checklist.max(by: { $0.sortOrder < $1.sortOrder })?.sortOrder ?? -1
        let item = ChecklistItem(title: newChecklistTitle, sortOrder: maxOrder + 1)
        todo.checklist.append(item)
        todo.markDirty()
        newChecklistTitle = ""
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func priorityIcon(for priority: Priority) -> String {
        switch priority {
        case .none: return "circle"
        case .low: return "arrow.down.circle"
        case .medium: return "minus.circle"
        case .high: return "exclamationmark.circle.fill"
        }
    }

    private func priorityPickerColor(for priority: Priority) -> Color {
        switch priority {
        case .none: return .secondary
        case .low: return .blue
        case .medium: return .orange
        case .high: return Color.attentionDanger
        }
    }
}

// MARK: - iOS Projects View

struct iOSProjectsView: View {
    @Environment(TodoListViewModel.self) private var viewModel
    @State private var showCreateProject = false
    @State private var newProjectTitle = ""

    // Group projects by area
    private var groupedProjects: [(area: Area?, projects: [Project])] {
        var groups: [(area: Area?, projects: [Project])] = []

        // Projects with areas
        var areaMap: [UUID: (area: Area, projects: [Project])] = [:]
        var noAreaProjects: [Project] = []

        for project in viewModel.projects {
            if let area = project.area {
                if areaMap[area.id] != nil {
                    areaMap[area.id]!.projects.append(project)
                } else {
                    areaMap[area.id] = (area: area, projects: [project])
                }
            } else {
                noAreaProjects.append(project)
            }
        }

        // Add no-area projects first
        if !noAreaProjects.isEmpty {
            groups.append((area: nil, projects: noAreaProjects))
        }

        // Add area-grouped projects
        for (_, value) in areaMap.sorted(by: { $0.value.area.sortOrder < $1.value.area.sortOrder }) {
            groups.append((area: value.area, projects: value.projects))
        }

        return groups
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(groupedProjects.enumerated()), id: \.offset) { _, group in
                    Section {
                        ForEach(group.projects) { project in
                            NavigationLink(value: project) {
                                projectRow(project)
                            }
                        }
                    } header: {
                        if let area = group.area {
                            Label(area.title, systemImage: "folder.fill")
                        }
                    }
                }
            }
            .navigationTitle("Projects")
            .navigationDestination(for: Project.self) { project in
                iOSTodoListView(sidebarItem: .project(project))
            }
            .overlay {
                if viewModel.projects.isEmpty {
                    ContentUnavailableView {
                        Label("No Projects", systemImage: "list.bullet.clipboard")
                    } description: {
                        Text("Create a project to organize related to-dos.")
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateProject = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showCreateProject) {
                createProjectSheet
            }
        }
    }

    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 14) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.attentionPrimary.opacity(0.15), lineWidth: 3)

                Circle()
                    .trim(from: 0, to: project.progress)
                    .stroke(Color.attentionPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(AttentionAnimation.springDefault, value: project.progress)

                if project.totalTodos > 0 {
                    Text("\(Int(project.progress * 100))%")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.attentionPrimary)
                }
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.title)
                    .font(.headline)

                if project.totalTodos > 0 {
                    Text("\(project.completedTodos)/\(project.totalTodos) completed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No tasks yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let deadline = project.deadline {
                Text(deadline.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption)
                    .foregroundStyle(Color.attentionWarning)
            }
        }
        .padding(.vertical, 4)
    }

    private var createProjectSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Project Name", text: $newProjectTitle)
                        .font(.headline)
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        newProjectTitle = ""
                        showCreateProject = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        viewModel.createProject(title: newProjectTitle)
                        newProjectTitle = ""
                        showCreateProject = false
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    }
                    .fontWeight(.semibold)
                    .disabled(newProjectTitle.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
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
