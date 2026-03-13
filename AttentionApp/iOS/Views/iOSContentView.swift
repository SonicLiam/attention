import SwiftUI
import SwiftData

// MARK: - Main iOS Content View

struct iOSContentView: View {
    @Environment(TodoListViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: iOSTab = .inbox

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

            Tab("Anytime", systemImage: "square.stack.fill", value: .anytime) {
                iOSTodoListView(sidebarItem: .anytime)
            }

            Tab("Browse", systemImage: "ellipsis.circle.fill", value: .browse) {
                iOSBrowseView()
            }
        }
        .tint(Color.attentionPrimary)
        .onAppear {
            viewModel.setup(modelContext: modelContext)
        }
    }
}

// MARK: - iOS Tab Enum

enum iOSTab: Hashable {
    case inbox
    case today
    case upcoming
    case anytime
    case browse
}

// MARK: - Browse View (Someday, Logbook, Projects)

struct iOSBrowseView: View {
    @Environment(TodoListViewModel.self) private var viewModel

    var body: some View {
        NavigationStack {
            List {
                Section("Lists") {
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

                Section("Projects") {
                    ForEach(viewModel.projects) { project in
                        NavigationLink {
                            iOSTodoListView(sidebarItem: .project(project))
                        } label: {
                            HStack {
                                Image(systemName: "list.bullet")
                                    .foregroundStyle(Color.attentionPrimary)

                                Text(project.title)

                                Spacer()

                                if project.totalTodos > 0 {
                                    CircularProgressView(progress: project.progress)
                                        .frame(width: 24, height: 24)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Browse")
            .onAppear {
                viewModel.loadSidebarData()
            }
        }
    }
}

// MARK: - iOS Todo List with Magic Plus FAB

struct iOSTodoListView: View {
    let sidebarItem: SidebarItem
    @Environment(TodoListViewModel.self) private var viewModel
    @State private var showNewTodo = false
    @State private var newTodoTitle = ""
    @State private var fabScale: CGFloat = 1.0
    @State private var showFABOptions = false
    @State private var newTodoPriority: Priority = .none
    @State private var newTodoScheduledDate: Date? = nil
    @State private var showSchedulePicker = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                List {
                    ForEach(viewModel.todos) { todo in
                        NavigationLink(value: todo) {
                            iOSTodoRowView(todo: todo)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                withAnimation(AttentionAnimation.springSnappy) {
                                    viewModel.completeTodo(todo)
                                }
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.success)
                            } label: {
                                Label("Done", systemImage: "checkmark.circle.fill")
                            }
                            .tint(Color.attentionSuccess)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                viewModel.moveTodoToToday(todo)
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                            } label: {
                                Label("Today", systemImage: "star.fill")
                            }
                            .tint(Color.sidebarToday)

                            Button {
                                viewModel.scheduleFor(todo, date: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                            } label: {
                                Label("Tomorrow", systemImage: "sunrise.fill")
                            }
                            .tint(Color.sidebarUpcoming)

                            Button(role: .destructive) {
                                withAnimation(AttentionAnimation.springSnappy) {
                                    viewModel.deleteTodo(todo)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .navigationTitle(sidebarItem.title)
                .navigationBarTitleDisplayMode(.large)
                .navigationDestination(for: Todo.self) { todo in
                    iOSTodoDetailView(todo: todo)
                }
                .refreshable {
                    viewModel.loadTodosForCurrentView()
                }

                // Magic Plus FAB
                magicPlusButton
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
            }
            .sheet(isPresented: $showNewTodo) {
                newTodoSheet
            }
            .confirmationDialog("New...", isPresented: $showFABOptions) {
                Button("New To-Do") {
                    newTodoPriority = .none
                    newTodoScheduledDate = nil
                    showNewTodo = true
                }
                Button("New To-Do for Today") {
                    newTodoPriority = .none
                    newTodoScheduledDate = Calendar.current.startOfDay(for: Date())
                    showNewTodo = true
                }
                Button("New To-Do (High Priority)") {
                    newTodoPriority = .high
                    newTodoScheduledDate = nil
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

    private var magicPlusButton: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            newTodoPriority = .none
            newTodoScheduledDate = nil
            showNewTodo = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.attentionPrimary, Color.attentionSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color.attentionPrimary.opacity(0.4), radius: 8, x: 0, y: 4)
                )
        }
        .scaleEffect(fabScale)
        .animation(AttentionAnimation.springBouncy, value: fabScale)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onChanged { _ in
                    fabScale = 0.9
                }
                .onEnded { _ in
                    fabScale = 1.0
                    let generator = UIImpactFeedbackGenerator(style: .heavy)
                    generator.impactOccurred()
                    showFABOptions = true
                }
        )
        .sensoryFeedback(.impact(flexibility: .solid), trigger: showNewTodo)
    }

    // MARK: - New Todo Sheet

    private var newTodoSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What do you want to do?", text: $newTodoTitle)
                        .font(.headline)
                }

                Section {
                    Picker("Priority", selection: $newTodoPriority) {
                        ForEach(Priority.allCases, id: \.self) { priority in
                            Label(priority.label, systemImage: priorityIcon(priority))
                                .tag(priority)
                        }
                    }

                    if let date = newTodoScheduledDate {
                        HStack {
                            Label("Scheduled", systemImage: "calendar")
                            Spacer()
                            Text(date.formatted(.dateTime.month(.abbreviated).day()))
                                .foregroundStyle(.secondary)
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
                        showNewTodo = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        viewModel.createTodo(title: newTodoTitle)
                        newTodoTitle = ""
                        newTodoPriority = .none
                        newTodoScheduledDate = nil
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
        .presentationDragIndicator(.visible)
    }

    private func priorityIcon(_ priority: Priority) -> String {
        switch priority {
        case .none: "minus"
        case .low: "arrow.down"
        case .medium: "equal"
        case .high: "exclamationmark"
        }
    }
}

// MARK: - iOS Todo Row (Enhanced)

struct iOSTodoRowView: View {
    let todo: Todo
    @Environment(TodoListViewModel.self) private var viewModel
    @State private var isChecked = false

    var body: some View {
        HStack(spacing: 12) {
            // Tappable checkbox
            Button {
                withAnimation(AttentionAnimation.springSnappy) {
                    isChecked = true
                }
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                // Delay completion to show animation
                DispatchQueue.main.asyncAfter(deadline: .now() + AttentionAnimation.completionDelay) {
                    viewModel.completeTodo(todo)
                }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(checkboxColor, lineWidth: 1.5)
                        .frame(width: AttentionLayout.checkboxSize, height: AttentionLayout.checkboxSize)

                    if isChecked {
                        Circle()
                            .fill(checkboxColor)
                            .frame(width: AttentionLayout.checkboxSize, height: AttentionLayout.checkboxSize)
                            .transition(.scale.combined(with: .opacity))

                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(todo.title)
                    .lineLimit(1)
                    .strikethrough(isChecked)
                    .foregroundStyle(isChecked ? .secondary : .primary)

                HStack(spacing: 6) {
                    if let date = todo.scheduledDate {
                        Label(
                            date.formatted(.dateTime.month(.abbreviated).day()),
                            systemImage: "calendar"
                        )
                        .font(.caption)
                        .foregroundStyle(todo.isOverdue ? Color.attentionDanger : .secondary)
                    }

                    if let deadline = todo.deadline {
                        Label(
                            deadline.formatted(.dateTime.month(.abbreviated).day()),
                            systemImage: "flag.fill"
                        )
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
                        let total = todo.checklist.count
                        Label("\(completed)/\(total)", systemImage: "checklist")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let project = todo.project {
                        Label(project.title, systemImage: "list.bullet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
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
        .contentShape(Rectangle())
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

// MARK: - iOS Todo Detail View (Full-Featured)

struct iOSTodoDetailView: View {
    let todo: Todo
    @Environment(TodoListViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var priority: Priority = .none
    @State private var scheduledDate: Date? = nil
    @State private var deadline: Date? = nil
    @State private var showScheduleDatePicker = false
    @State private var showDeadlineDatePicker = false
    @State private var tempScheduledDate = Date()
    @State private var tempDeadlineDate = Date()
    @State private var newChecklistTitle = ""

    var body: some View {
        Form {
            // Title section
            Section {
                TextField("Title", text: $title)
                    .font(.headline)
            }

            // Schedule section
            Section("Schedule") {
                // Scheduled date
                HStack {
                    Label("When", systemImage: "calendar")
                    Spacer()
                    if let date = scheduledDate {
                        Text(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .foregroundStyle(Color.attentionPrimary)
                    } else {
                        Text("No date")
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    tempScheduledDate = scheduledDate ?? Date()
                    showScheduleDatePicker.toggle()
                }

                if showScheduleDatePicker {
                    DatePicker(
                        "Scheduled Date",
                        selection: $tempScheduledDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .tint(Color.attentionPrimary)
                    .onChange(of: tempScheduledDate) { _, newVal in
                        scheduledDate = newVal
                    }

                    Button("Clear Date", role: .destructive) {
                        scheduledDate = nil
                        showScheduleDatePicker = false
                    }
                    .font(.subheadline)
                }

                // Deadline
                HStack {
                    Label("Deadline", systemImage: "flag.fill")
                        .foregroundStyle(deadline != nil ? Color.attentionWarning : .primary)
                    Spacer()
                    if let dl = deadline {
                        Text(dl.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .foregroundStyle(Color.attentionWarning)
                    } else {
                        Text("None")
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    tempDeadlineDate = deadline ?? Date()
                    showDeadlineDatePicker.toggle()
                }

                if showDeadlineDatePicker {
                    DatePicker(
                        "Deadline",
                        selection: $tempDeadlineDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .tint(Color.attentionWarning)
                    .onChange(of: tempDeadlineDate) { _, newVal in
                        deadline = newVal
                    }

                    Button("Clear Deadline", role: .destructive) {
                        deadline = nil
                        showDeadlineDatePicker = false
                    }
                    .font(.subheadline)
                }
            }

            // Priority section
            Section("Priority") {
                Picker("Priority", selection: $priority) {
                    ForEach(Priority.allCases, id: \.self) { p in
                        HStack {
                            Circle()
                                .fill(priorityPickerColor(p))
                                .frame(width: 8, height: 8)
                            Text(p.label)
                        }
                        .tag(p)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Tags section
            if !todo.tags.isEmpty {
                Section("Tags") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(todo.tags) { tag in
                                TagChipView(tag: tag)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            // Project
            if let project = todo.project {
                Section("Project") {
                    Label(project.title, systemImage: "list.bullet")
                        .foregroundStyle(Color.attentionPrimary)
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
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                        } label: {
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isCompleted ? Color.attentionSuccess : .secondary)
                                .font(.system(size: 20))
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
                    TextField("Add item...", text: $newChecklistTitle)
                        .onSubmit {
                            addChecklistItem()
                        }
                }
            }

            // Notes section
            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 120)
            }
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveChanges()
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            title = todo.title
            notes = todo.notes
            priority = todo.priority
            scheduledDate = todo.scheduledDate
            deadline = todo.deadline
        }
    }

    private func saveChanges() {
        todo.title = title
        todo.notes = notes
        todo.priority = priority
        todo.scheduledDate = scheduledDate
        todo.deadline = deadline
        if scheduledDate != nil && todo.status == .inbox {
            todo.status = .active
        }
        todo.markDirty()
    }

    private func addChecklistItem() {
        guard !newChecklistTitle.isEmpty else { return }
        let maxOrder = todo.checklist.max(by: { $0.sortOrder < $1.sortOrder })?.sortOrder ?? -1
        let item = ChecklistItem(title: newChecklistTitle, sortOrder: maxOrder + 1)
        todo.checklist.append(item)
        todo.markDirty()
        newChecklistTitle = ""
    }

    private func priorityPickerColor(_ priority: Priority) -> Color {
        switch priority {
        case .none: .gray
        case .low: .blue
        case .medium: .orange
        case .high: Color.attentionDanger
        }
    }
}

// MARK: - Tag Chip View

struct TagChipView: View {
    let tag: Tag

    var body: some View {
        Text(tag.title)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color(hex: tag.color).opacity(0.15))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color(hex: tag.color).opacity(0.3), lineWidth: 1)
            )
            .foregroundStyle(Color(hex: tag.color))
    }
}

// MARK: - iOS Projects View (Enhanced)

struct iOSProjectsView: View {
    @Environment(TodoListViewModel.self) private var viewModel
    @State private var showCreateProject = false
    @State private var newProjectTitle = ""

    private var projectsByArea: [(area: Area?, projects: [Project])] {
        var grouped: [UUID?: [Project]] = [:]
        for project in viewModel.projects {
            let key = project.area?.id
            grouped[key, default: []].append(project)
        }

        var result: [(area: Area?, projects: [Project])] = []

        // No-area projects first
        if let noArea = grouped[nil] {
            result.append((area: nil, projects: noArea))
        }

        // Area-grouped projects
        for (key, projects) in grouped where key != nil {
            if let area = projects.first?.area {
                result.append((area: area, projects: projects))
            }
        }

        return result
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(projectsByArea, id: \.area?.id) { group in
                    Section(group.area?.title ?? "No Area") {
                        ForEach(group.projects) { project in
                            NavigationLink(value: project) {
                                ProjectRowView(project: project)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Projects")
            .navigationDestination(for: Project.self) { project in
                iOSTodoListView(sidebarItem: .project(project))
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
            .onAppear {
                viewModel.loadSidebarData()
            }
        }
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
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Project Row with Progress Ring

struct ProjectRowView: View {
    let project: Project
    @State private var animatedProgress: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 3)

                Circle()
                    .trim(from: 0, to: animatedProgress)
                    .stroke(
                        LinearGradient(
                            colors: [Color.attentionPrimary, Color.attentionSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                if project.totalTodos > 0 {
                    Text("\(Int(project.progress * 100))%")
                        .font(.system(size: 9, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.title)
                    .font(.headline)

                HStack(spacing: 4) {
                    if project.totalTodos > 0 {
                        Text("\(project.completedTodos)/\(project.totalTodos) completed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No to-dos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let area = project.area {
                        Text("  \(area.title)")
                            .font(.caption)
                            .foregroundStyle(Color.attentionPrimary)
                    }
                }
            }

            Spacer()

            if let deadline = project.deadline {
                VStack {
                    Text(deadline.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption2)
                        .foregroundStyle(Color.attentionWarning)
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            withAnimation(AttentionAnimation.springDefault.delay(0.1)) {
                animatedProgress = project.progress
            }
        }
    }
}

// MARK: - Circular Progress View (Polished)

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
