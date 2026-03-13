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
        case .inbox: .blue
        case .today: .yellow
        case .upcoming: .red
        case .anytime: .indigo
        case .someday: .orange
        case .logbook: .green
        case .trash: .gray
        case .project: .indigo
        case .area: .purple
        case .tag: .pink
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

    private var todoRepository: TodoRepository?
    private var projectRepository: ProjectRepository?

    func setup(modelContext: ModelContext) {
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
                // Someday todos have no scheduled date and a special marker
                todos = try repo.fetchAnytime() // Will refine later
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
        guard let projectRepo = projectRepository else { return }
        do {
            projects = try projectRepo.fetchActive()
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
        refresh()
    }

    func permanentlyDelete(_ todo: Todo) {
        todoRepository?.delete(todo)
        try? todoRepository?.save()
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

    // MARK: - Project Actions

    func createProject(title: String) {
        guard let repo = projectRepository, !title.isEmpty else { return }
        repo.createProject(title: title)
        try? repo.save()
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
            default: return 0
            }
        } catch {
            return 0
        }
    }
}
