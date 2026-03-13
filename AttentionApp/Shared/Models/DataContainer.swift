import Foundation
import SwiftData

enum DataContainer {
    static let schema = Schema([
        Todo.self,
        Project.self,
        Area.self,
        Tag.self,
        ChecklistItem.self,
        Recurrence.self,
        Heading.self,
    ])

    static func create(inMemory: Bool = false) -> ModelContainer {
        let config = ModelConfiguration(
            "Attention",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            groupContainer: .automatic,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    /// In-memory container for previews and testing
    static var preview: ModelContainer {
        create(inMemory: true)
    }
}
