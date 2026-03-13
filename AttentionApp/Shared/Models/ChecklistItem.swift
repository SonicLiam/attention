import Foundation
import SwiftData

@Model
final class ChecklistItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var isCompleted: Bool
    var sortOrder: Int
    var createdAt: Date

    @Relationship(inverse: \Todo.checklist) var todo: Todo?

    init(title: String, sortOrder: Int = 0) {
        self.id = UUID()
        self.title = title
        self.isCompleted = false
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    func toggle() {
        isCompleted.toggle()
        todo?.markDirty()
    }
}
