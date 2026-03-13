import Foundation
import SwiftData

// MARK: - Project Status

enum ProjectStatus: String, Codable, CaseIterable {
    case active
    case completed
    case cancelled
}

// MARK: - Heading (Project Section)

@Model
final class Heading {
    @Attribute(.unique) var id: UUID
    var title: String
    var sortOrder: Int
    @Relationship(inverse: \Project.headings) var project: Project?

    init(title: String, sortOrder: Int = 0) {
        self.id = UUID()
        self.title = title
        self.sortOrder = sortOrder
    }
}

// MARK: - Project Model

@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var status: ProjectStatus
    var deadline: Date?
    var sortOrder: Int
    var createdAt: Date
    var modifiedAt: Date

    // Relationships
    @Relationship(deleteRule: .nullify) var todos: [Todo]
    @Relationship(deleteRule: .cascade) var headings: [Heading]
    @Relationship(inverse: \Area.projects) var area: Area?

    // Sync metadata
    var syncId: String?
    var lastSyncedAt: Date?
    var isDirty: Bool

    init(title: String, notes: String = "") {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.status = .active
        self.sortOrder = 0
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.todos = []
        self.headings = []
        self.isDirty = true
    }

    // MARK: - Computed

    var isCompleted: Bool { status == .completed }

    var totalTodos: Int { todos.count }

    var completedTodos: Int {
        todos.filter { $0.isCompleted }.count
    }

    var progress: Double {
        guard totalTodos > 0 else { return 0 }
        return Double(completedTodos) / Double(totalTodos)
    }

    var activeTodos: [Todo] {
        todos.filter { $0.isActive }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Actions

    func complete() {
        status = .completed
        modifiedAt = Date()
        isDirty = true
    }

    func markDirty() {
        modifiedAt = Date()
        isDirty = true
    }
}
