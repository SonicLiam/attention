import Foundation
import SwiftData
import SwiftUI

/// Represents the different list views in the sidebar
enum SidebarItem: Hashable, Identifiable {
    case inbox
    case today
    case upcoming
    case anytime
    case someday
    case logbook
    case trash
    case project(Project)
    case area(Area)
    case tag(Tag)

    var id: String {
        switch self {
        case .inbox: "inbox"
        case .today: "today"
        case .upcoming: "upcoming"
        case .anytime: "anytime"
        case .someday: "someday"
        case .logbook: "logbook"
        case .trash: "trash"
        case .project(let p): "project-\(p.id)"
        case .area(let a): "area-\(a.id)"
        case .tag(let t): "tag-\(t.id)"
        }
    }

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .anytime: "Anytime"
        case .someday: "Someday"
        case .logbook: "Logbook"
        case .trash: "Trash"
        case .project(let p): p.title
        case .area(let a): a.title
        case .tag(let t): t.title
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: "tray"
        case .today: "star"
        case .upcoming: "calendar"
        case .anytime: "square.stack"
        case .someday: "archivebox"
        case .logbook: "book"
        case .trash: "trash"
        case .project: "list.bullet"
        case .area: "folder"
        case .tag: "tag"
        }
    }

    var accentColor: Color {
        switch self {
        case .inbox: .sidebarInbox
        case .today: .sidebarToday
        case .upcoming: .sidebarUpcoming
        case .anytime: .sidebarAnytime
        case .someday: .sidebarSomeday
        case .logbook: .sidebarLogbook
        case .trash: .gray
        case .project: Color.attentionPrimary
        case .area: .purple
        case .tag: Color.attentionAccent
        }
    }
}

@MainActor
@Observable
final class TodoListViewModel {
    var selectedSidebarItem: SidebarItem? = .inbox
    var todos: [Todo] = []
    var projects: [Project] = []
    var areas: [Area] = []
    var tags: [Tag] = []
    var searchQuery: String = ""
    var isCreatingTodo: Bool = false
    var selectedTodo: Todo?
    var errorMessage: String?
    var showQuickEntry: Bool = false
    var showLogbook: Bool = false

    // Sync
    var syncEngine: SyncEngine?

    // Batch selection (macOS)
    var selectedTodos: Set<UUID> = []
    var isBatchMode: Bool { !selectedTodos.isEmpty }
    var lastSelectedIndex: Int?

    private var todoRepository: TodoRepository?
    private var projectRepository: ProjectRepository?
    private(set) var modelContext: ModelContext?

    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
        todoRepository = TodoRepository(modelContext: modelContext)
        projectRepository = ProjectRepository(modelContext: modelContext)
        refresh()
    }

    // MARK: - Data Loading

    func refresh() {
        loadTodosForCurrentView()
        loadSidebarData()
    }

    func loadTodosForCurrentView() {
        guard let repo = todoRepository else { return }
        do {
            switch selectedSidebarItem {
            case .inbox:
                todos = try repo.fetchInbox()
            case .today:
                todos = try repo.fetchToday()
            case .upcoming:
                todos = try repo.fetchUpcoming()
            case .anytime:
                todos = try repo.fetchAnytime()
            case .someday:
                todos = try repo.fetchAnytime()
            case .logbook:
                todos = try repo.fetchCompleted()
            case .trash:
                todos = try repo.fetchByStatus(.cancelled)
            case .project(let project):
                todos = try repo.fetchByProject(project)
            case .tag(let tag):
                todos = try repo.fetchByTag(tag)
            case .area, .none:
                todos = []
            }

            if !searchQuery.isEmpty {
                todos = try repo.search(query: searchQuery)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadSidebarData() {
        guard let ctx = modelContext else { return }
        do {
            let projectRepo = ProjectRepository(modelContext: ctx)
            projects = try projectRepo.fetchActive()

            let areaDescriptor = FetchDescriptor<Area>(sortBy: [SortDescriptor(\.sortOrder)])
            areas = try ctx.fetch(areaDescriptor)

            let tagDescriptor = FetchDescriptor<Tag>(sortBy: [SortDescriptor(\.sortOrder)])
            tags = try ctx.fetch(tagDescriptor).filter { $0.parentTag == nil }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Todo Actions

    func createTodo(title: String) {
        guard let repo = todoRepository, !title.isEmpty else { return }

        let status: TodoStatus
        let scheduledDate: Date?
        let project: Project?

        switch selectedSidebarItem {
        case .today:
            status = .active
            scheduledDate = Calendar.current.startOfDay(for: Date())
            project = nil
        case .project(let p):
            status = .active
            scheduledDate = nil
            project = p
        default:
            status = .inbox
            scheduledDate = nil
            project = nil
        }

        repo.createTodo(
            title: title,
            status: status,
            scheduledDate: scheduledDate,
            project: project
        )

        try? repo.save()
        notifySync()
        refresh()
    }

    func createTodoWithDetails(
        title: String,
        scheduledDate: Date? = nil,
        priority: Priority = .none,
        project: Project? = nil
    ) {
        guard let repo = todoRepository, !title.isEmpty else { return }
        let status: TodoStatus = scheduledDate != nil ? .active : .inbox
        let todo = repo.createTodo(
            title: title,
            status: status,
            priority: priority,
            scheduledDate: scheduledDate,
            project: project
        )
        if let project { todo.project = project }
        try? repo.save()
        notifySync()
        refresh()
    }

    func completeTodo(_ todo: Todo) {
        if todo.recurrence != nil {
            completeRecurringTodo(todo)
        } else {
            todo.complete()
            NotificationService.shared.cancelNotifications(for: todo.id)
            try? todoRepository?.save()
            notifySync()
            refresh()
        }
    }

    func uncompleteTodo(_ todo: Todo) {
        todo.uncomplete()
        try? todoRepository?.save()
        notifySync()
        refresh()
    }

    func deleteTodo(_ todo: Todo) {
        NotificationService.shared.cancelNotifications(for: todo.id)
        todo.cancel()
        try? todoRepository?.save()
        notifySync()
        if selectedTodo?.id == todo.id {
            selectedTodo = nil
        }
        refresh()
    }

    func permanentlyDelete(_ todo: Todo) {
        todoRepository?.delete(todo)
        try? todoRepository?.save()
        notifySync()
        if selectedTodo?.id == todo.id {
            selectedTodo = nil
        }
        refresh()
    }

    func moveTodoToToday(_ todo: Todo) {
        todo.scheduleForToday()
        try? todoRepository?.save()
        notifySync()
        refresh()
    }

    func scheduleFor(_ todo: Todo, date: Date) {
        todo.scheduleFor(date)
        try? todoRepository?.save()
        notifySync()
        refresh()
    }

    func setPriority(_ todo: Todo, priority: Priority) {
        todo.priority = priority
        todo.markDirty()
        try? todoRepository?.save()
        notifySync()
        refresh()
    }

    func moveToProject(_ todo: Todo, project: Project?) {
        todo.project = project
        todo.markDirty()
        try? todoRepository?.save()
        notifySync()
        refresh()
    }

    func addChecklistItem(to todo: Todo, title: String) {
        guard let ctx = modelContext, !title.isEmpty else { return }
        let maxOrder = todo.checklist.max(by: { $0.sortOrder < $1.sortOrder })?.sortOrder ?? -1
        let item = ChecklistItem(title: title, sortOrder: maxOrder + 1)
        item.todo = todo
        ctx.insert(item)
        todo.markDirty()
        try? ctx.save()
    }

    func removeChecklistItem(_ item: ChecklistItem, from todo: Todo) {
        guard let ctx = modelContext else { return }
        ctx.delete(item)
        todo.markDirty()
        try? ctx.save()
    }

    func toggleTag(_ tag: Tag, on todo: Todo) {
        if todo.tags.contains(where: { $0.id == tag.id }) {
            todo.tags.removeAll { $0.id == tag.id }
        } else {
            todo.tags.append(tag)
        }
        todo.markDirty()
        try? todoRepository?.save()
    }

    func saveTodo() {
        try? todoRepository?.save()
        notifySync()
    }

    // MARK: - Sync Integration

    private func notifySync() {
        syncEngine?.triggerSync()
    }

    private func saveAndSync() {
        try? todoRepository?.save()
        notifySync()
    }

    // MARK: - Project Actions

    func createProject(title: String) {
        guard let repo = projectRepository, !title.isEmpty else { return }
        repo.createProject(title: title)
        try? repo.save()
        loadSidebarData()
    }

    func createArea(title: String) {
        guard let ctx = modelContext, !title.isEmpty else { return }
        let area = Area(title: title)
        ctx.insert(area)
        try? ctx.save()
        loadSidebarData()
    }

    // MARK: - Counts for Sidebar

    func count(for item: SidebarItem) -> Int {
        guard let repo = todoRepository else { return 0 }
        do {
            switch item {
            case .inbox: return try repo.fetchInbox().count
            case .today: return try repo.fetchToday().count
            case .upcoming: return try repo.fetchUpcoming().count
            case .project(let p): return try repo.fetchByProject(p).count
            default: return 0
            }
        } catch {
            return 0
        }
    }

    // MARK: - Drag & Drop Reordering

    func reorderTodos(_ source: IndexSet, to destination: Int) {
        var reordered = todos
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, todo) in reordered.enumerated() {
            todo.sortOrder = index
            todo.markDirty()
        }
        todos = reordered
        try? todoRepository?.save()
    }

    func reorderChecklistItems(_ source: IndexSet, to destination: Int, in todo: Todo) {
        var items = todo.checklist.sorted { $0.sortOrder < $1.sortOrder }
        items.move(fromOffsets: source, toOffset: destination)
        for (index, item) in items.enumerated() {
            item.sortOrder = index
        }
        todo.markDirty()
        try? todoRepository?.save()
    }

    func moveTodo(_ todo: Todo, to sidebarItem: SidebarItem) {
        switch sidebarItem {
        case .inbox:
            todo.moveToInbox()
        case .today:
            todo.scheduleForToday()
        case .someday:
            todo.moveToSomeday()
        case .anytime:
            todo.scheduledDate = nil
            todo.status = .active
            todo.project = nil
            todo.markDirty()
        case .project(let project):
            todo.project = project
            todo.status = .active
            todo.markDirty()
        case .area(let area):
            todo.area = area
            todo.markDirty()
        default:
            break
        }
        try? todoRepository?.save()
        refresh()
    }

    // MARK: - Batch Operations

    func toggleBatchSelection(_ todo: Todo) {
        if selectedTodos.contains(todo.id) {
            selectedTodos.remove(todo.id)
        } else {
            selectedTodos.insert(todo.id)
        }
        if let index = todos.firstIndex(where: { $0.id == todo.id }) {
            lastSelectedIndex = index
        }
    }

    func rangeSelect(to todo: Todo) {
        guard let lastIdx = lastSelectedIndex,
              let currentIdx = todos.firstIndex(where: { $0.id == todo.id }) else {
            toggleBatchSelection(todo)
            return
        }
        let range = min(lastIdx, currentIdx)...max(lastIdx, currentIdx)
        for i in range {
            selectedTodos.insert(todos[i].id)
        }
    }

    func clearBatchSelection() {
        selectedTodos.removeAll()
        lastSelectedIndex = nil
    }

    func batchComplete() {
        let todosToComplete = todos.filter { selectedTodos.contains($0.id) }
        for todo in todosToComplete {
            if todo.recurrence != nil {
                completeRecurringTodo(todo)
            } else {
                todo.complete()
            }
        }
        try? todoRepository?.save()
        clearBatchSelection()
        refresh()
    }

    func batchDelete() {
        let todosToDelete = todos.filter { selectedTodos.contains($0.id) }
        for todo in todosToDelete {
            NotificationService.shared.cancelNotifications(for: todo.id)
            todo.cancel()
        }
        try? todoRepository?.save()
        clearBatchSelection()
        refresh()
    }

    func batchMoveToToday() {
        let todosToMove = todos.filter { selectedTodos.contains($0.id) }
        for todo in todosToMove {
            todo.scheduleForToday()
        }
        try? todoRepository?.save()
        clearBatchSelection()
        refresh()
    }

    func batchSetPriority(_ priority: Priority) {
        let todosToUpdate = todos.filter { selectedTodos.contains($0.id) }
        for todo in todosToUpdate {
            todo.priority = priority
            todo.markDirty()
        }
        try? todoRepository?.save()
        clearBatchSelection()
        refresh()
    }

    func batchMoveToProject(_ project: Project?) {
        let todosToMove = todos.filter { selectedTodos.contains($0.id) }
        for todo in todosToMove {
            todo.project = project
            todo.markDirty()
        }
        try? todoRepository?.save()
        clearBatchSelection()
        refresh()
    }

    // MARK: - Recurrence

    func completeRecurringTodo(_ todo: Todo) {
        guard let recurrence = todo.recurrence,
              let ctx = modelContext else {
            todo.complete()
            try? todoRepository?.save()
            refresh()
            return
        }

        // Complete the current todo
        todo.complete()

        // Calculate next date
        let baseDate = todo.scheduledDate ?? Date()
        guard let nextDate = recurrence.nextDate(after: baseDate) else {
            // Recurrence ended
            try? todoRepository?.save()
            refresh()
            return
        }

        // Create next occurrence
        let nextTodo = Todo(
            title: todo.title,
            notes: todo.notes,
            status: .active,
            priority: todo.priority,
            scheduledDate: nextDate,
            deadline: todo.deadline.flatMap { deadline in
                // Shift deadline by same interval
                let diff = nextDate.timeIntervalSince(baseDate)
                return deadline.addingTimeInterval(diff)
            }
        )
        nextTodo.project = todo.project
        nextTodo.area = todo.area
        nextTodo.tags = todo.tags

        // Clone recurrence
        let newRecurrence = Recurrence(
            frequency: recurrence.frequency,
            interval: recurrence.interval,
            daysOfWeek: recurrence.daysOfWeek,
            dayOfMonth: recurrence.dayOfMonth,
            endDate: recurrence.endDate
        )
        ctx.insert(newRecurrence)
        nextTodo.recurrence = newRecurrence

        // Clone reminder settings
        nextTodo.reminderDate = nextDate
        nextTodo.reminderOffset = todo.reminderOffset

        ctx.insert(nextTodo)

        // Schedule notification for next occurrence
        if let offset = todo.reminderOffset {
            NotificationService.shared.scheduleNotification(
                for: nextTodo.id, title: nextTodo.title, date: nextDate, offset: offset
            )
        }

        // Cancel notification for completed todo
        NotificationService.shared.cancelNotifications(for: todo.id)

        try? todoRepository?.save()
        refresh()
    }

    // MARK: - Reminder / Notifications

    func setReminder(for todo: Todo, date: Date, offset: ReminderOffset) {
        todo.reminderDate = date
        todo.reminderOffset = offset
        todo.markDirty()
        try? todoRepository?.save()

        NotificationService.shared.scheduleNotification(
            for: todo.id, title: todo.title, date: date, offset: offset
        )
    }

    func removeReminder(for todo: Todo) {
        todo.reminderDate = nil
        todo.reminderOffset = nil
        todo.markDirty()
        try? todoRepository?.save()
        NotificationService.shared.cancelNotifications(for: todo.id)
    }

    // MARK: - Keyboard Navigation

    func selectNextTodo() {
        guard !todos.isEmpty else { return }
        if let current = selectedTodo,
           let idx = todos.firstIndex(where: { $0.id == current.id }),
           idx + 1 < todos.count {
            selectedTodo = todos[idx + 1]
        } else {
            selectedTodo = todos.first
        }
    }

    func selectPreviousTodo() {
        guard !todos.isEmpty else { return }
        if let current = selectedTodo,
           let idx = todos.firstIndex(where: { $0.id == current.id }),
           idx > 0 {
            selectedTodo = todos[idx - 1]
        } else {
            selectedTodo = todos.last
        }
    }

    func cyclePriority() {
        guard let todo = selectedTodo else { return }
        let next: Priority
        switch todo.priority {
        case .none: next = .low
        case .low: next = .medium
        case .medium: next = .high
        case .high: next = .none
        }
        setPriority(todo, priority: next)
    }
}
