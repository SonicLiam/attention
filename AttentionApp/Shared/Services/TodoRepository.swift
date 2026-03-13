import Foundation
import SwiftData

@MainActor
final class TodoRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Create

    @discardableResult
    func createTodo(
        title: String,
        notes: String = "",
        status: TodoStatus = .inbox,
        priority: Priority = .none,
        scheduledDate: Date? = nil,
        deadline: Date? = nil,
        project: Project? = nil,
        area: Area? = nil,
        tags: [Tag] = []
    ) -> Todo {
        let todo = Todo(
            title: title,
            notes: notes,
            status: status,
            priority: priority,
            scheduledDate: scheduledDate,
            deadline: deadline
        )
        todo.project = project
        todo.area = area
        todo.tags = tags

        // Set sort order to end of list
        let maxOrder = (try? fetchAll().max(by: { $0.sortOrder < $1.sortOrder })?.sortOrder) ?? -1
        todo.sortOrder = maxOrder + 1

        modelContext.insert(todo)
        return todo
    }

    // MARK: - Read

    func fetchAll() throws -> [Todo] {
        let descriptor = FetchDescriptor<Todo>(sortBy: [SortDescriptor(\.sortOrder)])
        return try modelContext.fetch(descriptor)
    }

    func fetchByStatus(_ status: TodoStatus) throws -> [Todo] {
        let descriptor = FetchDescriptor<Todo>(
            predicate: #Predicate { $0.status == status },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchInbox() throws -> [Todo] {
        let inboxStatus = TodoStatus.inbox
        return try fetchByStatus(inboxStatus)
    }

    func fetchToday() throws -> [Todo] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        let activeStatus = TodoStatus.active
        let inboxStatus = TodoStatus.inbox

        let descriptor = FetchDescriptor<Todo>(
            predicate: #Predicate {
                ($0.status == activeStatus || $0.status == inboxStatus) &&
                $0.scheduledDate != nil &&
                $0.scheduledDate! >= startOfDay &&
                $0.scheduledDate! < endOfDay
            },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchUpcoming() throws -> [Todo] {
        let startOfTomorrow = Calendar.current.date(
            byAdding: .day, value: 1,
            to: Calendar.current.startOfDay(for: Date())
        )!
        let activeStatus = TodoStatus.active
        let inboxStatus = TodoStatus.inbox

        let descriptor = FetchDescriptor<Todo>(
            predicate: #Predicate {
                ($0.status == activeStatus || $0.status == inboxStatus) &&
                $0.scheduledDate != nil &&
                $0.scheduledDate! >= startOfTomorrow
            },
            sortBy: [SortDescriptor(\.scheduledDate)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchAnytime() throws -> [Todo] {
        let activeStatus = TodoStatus.active
        let descriptor = FetchDescriptor<Todo>(
            predicate: #Predicate {
                $0.status == activeStatus && $0.scheduledDate == nil
            },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchCompleted() throws -> [Todo] {
        let completedStatus = TodoStatus.completed
        let descriptor = FetchDescriptor<Todo>(
            predicate: #Predicate { $0.status == completedStatus },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchByProject(_ project: Project) throws -> [Todo] {
        let projectId = project.id
        let descriptor = FetchDescriptor<Todo>(
            predicate: #Predicate { $0.project?.id == projectId },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchByTag(_ tag: Tag) throws -> [Todo] {
        let activeStatus = TodoStatus.active
        let inboxStatus = TodoStatus.inbox
        let descriptor = FetchDescriptor<Todo>(
            predicate: #Predicate {
                $0.status == activeStatus || $0.status == inboxStatus
            },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let todos = try modelContext.fetch(descriptor)
        return todos.filter { $0.tags.contains(where: { $0.id == tag.id }) }
    }

    func search(query: String) throws -> [Todo] {
        let descriptor = FetchDescriptor<Todo>(
            predicate: #Predicate {
                $0.title.localizedStandardContains(query) ||
                $0.notes.localizedStandardContains(query)
            },
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchDirty() throws -> [Todo] {
        let descriptor = FetchDescriptor<Todo>(
            predicate: #Predicate { $0.isDirty == true }
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Update

    func update(_ todo: Todo, title: String? = nil, notes: String? = nil, priority: Priority? = nil) {
        if let title { todo.title = title }
        if let notes { todo.notes = notes }
        if let priority { todo.priority = priority }
        todo.markDirty()
    }

    // MARK: - Delete

    func delete(_ todo: Todo) {
        modelContext.delete(todo)
    }

    func deleteCancelled() throws {
        let cancelledStatus = TodoStatus.cancelled
        let cancelled = try fetchByStatus(cancelledStatus)
        for todo in cancelled {
            modelContext.delete(todo)
        }
    }

    // MARK: - Save

    func save() throws {
        try modelContext.save()
    }
}
