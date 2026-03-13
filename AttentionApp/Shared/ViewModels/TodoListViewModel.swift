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
        refresh()
    }

    func createTodoWithDetails(
        title: String,
        scheduledDate: Date? = nil,
        project: Project? = nil
    ) {
        guard let repo = todoRepository, !title.isEmpty else { return }
        let status: TodoStatus = scheduledDate != nil ? .active : .inbox
        repo.createTodo(
            title: title,
            status: status,
            scheduledDate: scheduledDate,
            project: project
        )
        try? repo.save()
        refresh()
    }

    func completeTodo(_ todo: Todo) {
        todo.complete()
        try? todoRepository?.save()
        refresh()
    }

    func uncompleteTodo(_ todo: Todo) {
        todo.uncomplete()
        try? todoRepository?.save()
        refresh()
    }

    func deleteTodo(_ todo: Todo) {
        todo.cancel()
        try? todoRepository?.save()
        if selectedTodo?.id == todo.id {
            selectedTodo = nil
        }
        refresh()
    }

    func permanentlyDelete(_ todo: Todo) {
        todoRepository?.delete(todo)
        try? todoRepository?.save()
        if selectedTodo?.id == todo.id {
            selectedTodo = nil
        }
        refresh()
    }

    func moveTodoToToday(_ todo: Todo) {
        todo.scheduleForToday()
        try? todoRepository?.save()
        refresh()
    }

    func scheduleFor(_ todo: Todo, date: Date) {
        todo.scheduleFor(date)
        try? todoRepository?.save()
        refresh()
    }

    func setPriority(_ todo: Todo, priority: Priority) {
        todo.priority = priority
        todo.markDirty()
        try? todoRepository?.save()
        refresh()
    }

    func moveToProject(_ todo: Todo, project: Project?) {
        todo.project = project
        todo.markDirty()
        try? todoRepository?.save()
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
}
