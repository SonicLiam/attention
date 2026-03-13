import Foundation
import SwiftData

@MainActor
final class ProjectRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Create

    @discardableResult
    func createProject(title: String, notes: String = "", area: Area? = nil) -> Project {
        let project = Project(title: title, notes: notes)
        project.area = area
        modelContext.insert(project)
        return project
    }

    @discardableResult
    func addHeading(to project: Project, title: String) -> Heading {
        let maxOrder = project.headings.max(by: { $0.sortOrder < $1.sortOrder })?.sortOrder ?? -1
        let heading = Heading(title: title, sortOrder: maxOrder + 1)
        heading.project = project
        modelContext.insert(heading)
        project.markDirty()
        return heading
    }

    // MARK: - Read

    func fetchAll() throws -> [Project] {
        let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\.sortOrder)])
        return try modelContext.fetch(descriptor)
    }

    func fetchActive() throws -> [Project] {
        let activeStatus = ProjectStatus.active
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.status == activeStatus },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchByArea(_ area: Area) throws -> [Project] {
        let areaId = area.id
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.area?.id == areaId },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Delete

    func delete(_ project: Project) {
        modelContext.delete(project)
    }

    func save() throws {
        try modelContext.save()
    }
}
