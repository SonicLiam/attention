import Foundation
import SwiftData

@Model
final class Tag {
    @Attribute(.unique) var id: UUID
    var title: String
    var color: String
    var sortOrder: Int
    var createdAt: Date
    var modifiedAt: Date

    // Relationships
    @Relationship var parentTag: Tag?
    @Relationship(inverse: \Tag.parentTag) var childTags: [Tag]
    @Relationship(inverse: \Todo.tags) var todos: [Todo]

    // Sync metadata
    var syncId: String?
    var isDirty: Bool

    init(title: String, color: String = "#6366F1") {
        self.id = UUID()
        self.title = title
        self.color = color
        self.sortOrder = 0
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.childTags = []
        self.todos = []
        self.isDirty = true
    }

    var hasChildren: Bool { !childTags.isEmpty }

    func markDirty() {
        modifiedAt = Date()
        isDirty = true
    }
}
