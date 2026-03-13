import Foundation
import SwiftData
import SwiftUI
import Combine

/// Filter criteria for searching todos
struct SearchFilter: Equatable {
    var selectedTagIds: Set<UUID> = []
    var priority: Priority?
    var startDate: Date?
    var endDate: Date?
    var status: TodoStatus?
    var groupByProject: Bool = false

    var isActive: Bool {
        !selectedTagIds.isEmpty || priority != nil || startDate != nil || endDate != nil || status != nil
    }

    mutating func reset() {
        selectedTagIds = []
        priority = nil
        startDate = nil
        endDate = nil
        status = nil
        groupByProject = false
    }
}

/// Grouped search results
struct SearchResultGroup: Identifiable {
    let id: String
    let title: String
    let todos: [Todo]
}

@MainActor
@Observable
final class SearchViewModel {
    var searchQuery: String = "" {
        didSet {
            scheduleSearch()
        }
    }
    var filter: SearchFilter = SearchFilter() {
        didSet {
            performSearch()
        }
    }
    var results: [Todo] = []
    var groupedResults: [SearchResultGroup] = []
    var isSearching: Bool = false
    var availableTags: [Tag] = []

    private var modelContext: ModelContext?
    private var searchTask: Task<Void, Never>?

    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadTags()
    }

    // MARK: - Debounced Search

    private func scheduleSearch() {
        searchTask?.cancel()
        guard !searchQuery.isEmpty || filter.isActive else {
            results = []
            groupedResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            performSearch()
        }
    }

    func performSearch() {
        guard let ctx = modelContext else { return }
        isSearching = true

        do {
            var todos: [Todo]

            if searchQuery.isEmpty {
                // Filter-only mode: fetch all active
                let descriptor = FetchDescriptor<Todo>(
                    sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
                )
                todos = try ctx.fetch(descriptor)
            } else {
                // Full-text search across titles and notes
                let query = searchQuery
                let descriptor = FetchDescriptor<Todo>(
                    predicate: #Predicate<Todo> {
                        $0.title.localizedStandardContains(query) ||
                        $0.notes.localizedStandardContains(query)
                    },
                    sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
                )
                todos = try ctx.fetch(descriptor)

                // Also search by project name and tag name (post-filter since predicates can't traverse relationships well)
                if todos.isEmpty {
                    let allDescriptor = FetchDescriptor<Todo>(
                        sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
                    )
                    let allTodos = try ctx.fetch(allDescriptor)
                    let lowercasedQuery = query.lowercased()
                    todos = allTodos.filter { todo in
                        todo.project?.title.lowercased().contains(lowercasedQuery) == true ||
                        todo.tags.contains(where: { $0.title.lowercased().contains(lowercasedQuery) })
                    }
                }
            }

            // Apply filters
            todos = applyFilters(todos)

            results = todos

            // Group results if requested
            if filter.groupByProject {
                groupedResults = groupByProject(todos)
            } else {
                groupedResults = [SearchResultGroup(id: "all", title: "Results", todos: todos)]
            }
        } catch {
            results = []
            groupedResults = []
        }

        isSearching = false
    }

    // MARK: - Filtering

    private func applyFilters(_ todos: [Todo]) -> [Todo] {
        var filtered = todos

        // Filter by tags
        if !filter.selectedTagIds.isEmpty {
            filtered = filtered.filter { todo in
                let todoTagIds = Set(todo.tags.map(\.id))
                return !filter.selectedTagIds.isDisjoint(with: todoTagIds)
            }
        }

        // Filter by priority
        if let priority = filter.priority {
            filtered = filtered.filter { $0.priority == priority }
        }

        // Filter by date range
        if let startDate = filter.startDate {
            filtered = filtered.filter { todo in
                guard let scheduled = todo.scheduledDate else { return false }
                return scheduled >= startDate
            }
        }
        if let endDate = filter.endDate {
            filtered = filtered.filter { todo in
                guard let scheduled = todo.scheduledDate else { return false }
                return scheduled <= endDate
            }
        }

        // Filter by status
        if let status = filter.status {
            filtered = filtered.filter { $0.status == status }
        }

        return filtered
    }

    // MARK: - Grouping

    private func groupByProject(_ todos: [Todo]) -> [SearchResultGroup] {
        var groups: [String: [Todo]] = [:]
        var noProjectTodos: [Todo] = []

        for todo in todos {
            if let project = todo.project {
                groups[project.title, default: []].append(todo)
            } else {
                noProjectTodos.append(todo)
            }
        }

        var result: [SearchResultGroup] = []

        for (title, projectTodos) in groups.sorted(by: { $0.key < $1.key }) {
            result.append(SearchResultGroup(id: title, title: title, todos: projectTodos))
        }

        if !noProjectTodos.isEmpty {
            result.append(SearchResultGroup(id: "no-project", title: "No Project", todos: noProjectTodos))
        }

        return result
    }

    // MARK: - Tags

    private func loadTags() {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<Tag>(sortBy: [SortDescriptor(\.sortOrder)])
        availableTags = (try? ctx.fetch(descriptor)) ?? []
    }

    func toggleTagFilter(_ tag: Tag) {
        if filter.selectedTagIds.contains(tag.id) {
            filter.selectedTagIds.remove(tag.id)
        } else {
            filter.selectedTagIds.insert(tag.id)
        }
    }

    func clearFilters() {
        filter.reset()
    }
}
