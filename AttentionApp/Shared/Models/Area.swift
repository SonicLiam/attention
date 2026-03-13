import Foundation
import SwiftData

@Model
final class Area {
    @Attribute(.unique) var id: UUID
    var title: String
    var sortOrder: Int
    var createdAt: Date
    var modifiedAt: Date

    // Relationships
    @Relationship(deleteRule: .nullify) var todos: [Todo]
    @Relationship(deleteRule: .nullify) var projects: [Project]

    // Sync metadata
    var syncId: String?
    var lastSyncedAt: Date?
    var isDirty: Bool

    init(title: String) {
        self.id = UUID()
        self.title = title
        self.sortOrder = 0
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.todos = []
        self.projects = []
        self.isDirty = true
    }

    /// All items (projects + standalone todos) sorted by sortOrder
    var allItems: [(any PersistentModel, Int)] {
        let projectItems = projects.map { ($0 as any PersistentModel, $0.sortOrder) }
        let todoItems = todos.filter { $0.project == nil }.map { ($0 as any PersistentModel, $0.sortOrder) }
        return (projectItems + todoItems).sorted { $0.1 < $1.1 }
    }

    func markDirty() {
        modifiedAt = Date()
        isDirty = true
    }
}
