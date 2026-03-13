import Foundation
import SwiftData

// MARK: - Sync Status

enum SyncStatus: Sendable {
    case idle
    case syncing
    case synced
    case offline
    case error(String)
}

// MARK: - Sync Engine

@MainActor
@Observable
final class SyncEngine {
    var syncStatus: SyncStatus = .idle
    var lastSyncId: Int {
        get { UserDefaults.standard.integer(forKey: "lastSyncId") }
        set { UserDefaults.standard.set(newValue, forKey: "lastSyncId") }
    }

    private let apiClient: APIClient
    private let webSocketClient: WebSocketClient
    private var modelContext: ModelContext?
    private var syncDebounceTask: Task<Void, Never>?
    private var isRunningSync = false

    init(apiClient: APIClient = .shared, webSocketClient: WebSocketClient) {
        self.apiClient = apiClient
        self.webSocketClient = webSocketClient
        setupWebSocketHandlers()
    }

    // MARK: - Setup

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - WebSocket Handlers

    private func setupWebSocketHandlers() {
        webSocketClient.onPushAck = { [weak self] ack in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let latestId = ack.latestSyncId, latestId > 0 {
                    self.lastSyncId = latestId
                }
                self.syncStatus = .synced
            }
        }

        webSocketClient.onPullResponse = { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let changes = response.changes {
                    self.applyRemoteChanges(changes)
                }
                if let latestId = response.latestSyncId {
                    self.lastSyncId = latestId
                }
                self.syncStatus = .synced
            }
        }

        webSocketClient.onRemoteChanges = { [weak self] msg in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let changes = msg.changes {
                    self.applyRemoteChanges(changes)
                }
            }
        }

        webSocketClient.onAuthFailure = { [weak self] in
            Task { @MainActor [weak self] in
                self?.syncStatus = .error("Authentication failed")
            }
        }
    }

    // MARK: - Connect

    func connectWebSocket() async {
        guard let token = await apiClient.accessToken else { return }
        webSocketClient.connect(token: token)
    }

    func disconnectWebSocket() {
        webSocketClient.disconnect()
    }

    // MARK: - Sync Trigger (debounced)

    func triggerSync() {
        syncDebounceTask?.cancel()
        syncDebounceTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await performSync()
        }
    }

    func triggerSyncImmediate() {
        syncDebounceTask?.cancel()
        Task {
            await performSync()
        }
    }

    // MARK: - Full Sync Cycle

    func performSync() async {
        guard !isRunningSync else { return }
        guard modelContext != nil else { return }

        isRunningSync = true
        syncStatus = .syncing

        do {
            // Step 1: Push dirty local entities
            try await pushDirtyEntities()

            // Step 2: Pull remote changes
            if webSocketClient.isConnected {
                webSocketClient.pullChanges(lastSyncId: lastSyncId)
            } else {
                try await pullViaHTTP()
            }

            syncStatus = .synced
        } catch {
            let isNetworkError: Bool
            if let apiError = error as? APIError {
                switch apiError {
                case .networkError, .invalidResponse:
                    isNetworkError = true
                default:
                    isNetworkError = false
                }
            } else {
                isNetworkError = (error as NSError).domain == NSURLErrorDomain
            }

            if isNetworkError {
                syncStatus = .offline
            } else {
                syncStatus = .error(error.localizedDescription)
            }
        }

        isRunningSync = false
    }

    // MARK: - Push Dirty Entities

    private func pushDirtyEntities() async throws {
        guard let ctx = modelContext else { return }

        var changes: [SyncChange] = []

        // Collect dirty todos
        let dirtyTodos = try fetchDirtyEntities(Todo.self, context: ctx)
        for todo in dirtyTodos {
            var data: [String: AnyCodableValue] = [
                "title": .string(todo.title),
                "notes": .string(todo.notes),
                "status": .string(todo.status.rawValue),
                "priority": .int(todo.priority.rawValue),
                "sortOrder": .int(todo.sortOrder),
            ]
            if let scheduledDate = todo.scheduledDate {
                data["scheduledDate"] = .string(ISO8601DateFormatter().string(from: scheduledDate))
            }
            if let deadline = todo.deadline {
                data["deadline"] = .string(ISO8601DateFormatter().string(from: deadline))
            }
            if let projectId = todo.project?.id {
                data["projectId"] = .string(projectId.uuidString)
            }
            if let areaId = todo.area?.id {
                data["areaId"] = .string(areaId.uuidString)
            }

            let action = todo.syncId == nil ? "create" : "update"
            changes.append(SyncChange(
                entityType: "todo",
                entityId: todo.id.uuidString,
                action: action,
                data: data,
                version: 1
            ))
        }

        // Collect dirty projects
        let dirtyProjects = try fetchDirtyEntities(Project.self, context: ctx)
        for project in dirtyProjects {
            var data: [String: AnyCodableValue] = [
                "title": .string(project.title),
                "notes": .string(project.notes),
                "status": .string(project.status.rawValue),
                "sortOrder": .int(project.sortOrder),
            ]
            if let deadline = project.deadline {
                data["deadline"] = .string(ISO8601DateFormatter().string(from: deadline))
            }
            if let areaId = project.area?.id {
                data["areaId"] = .string(areaId.uuidString)
            }

            let action = project.syncId == nil ? "create" : "update"
            changes.append(SyncChange(
                entityType: "project",
                entityId: project.id.uuidString,
                action: action,
                data: data,
                version: 1
            ))
        }

        // Collect dirty areas
        let dirtyAreas = try fetchDirtyEntities(Area.self, context: ctx)
        for area in dirtyAreas {
            let data: [String: AnyCodableValue] = [
                "title": .string(area.title),
                "sortOrder": .int(area.sortOrder),
            ]
            let action = area.syncId == nil ? "create" : "update"
            changes.append(SyncChange(
                entityType: "area",
                entityId: area.id.uuidString,
                action: action,
                data: data,
                version: 1
            ))
        }

        // Collect dirty tags
        let dirtyTags = try fetchDirtyEntities(Tag.self, context: ctx)
        for tag in dirtyTags {
            var data: [String: AnyCodableValue] = [
                "title": .string(tag.title),
                "color": .string(tag.color),
                "sortOrder": .int(tag.sortOrder),
            ]
            if let parentId = tag.parentTag?.id {
                data["parentTagId"] = .string(parentId.uuidString)
            }
            let action = tag.syncId == nil ? "create" : "update"
            changes.append(SyncChange(
                entityType: "tag",
                entityId: tag.id.uuidString,
                action: action,
                data: data,
                version: 1
            ))
        }

        guard !changes.isEmpty else { return }

        // Push via WebSocket if connected, else via HTTP (push not directly available via HTTP, use WS)
        if webSocketClient.isConnected {
            webSocketClient.pushChanges(changes)
            // Mark entities clean after push
            markEntitiesClean(todos: dirtyTodos, projects: dirtyProjects, areas: dirtyAreas, tags: dirtyTags)
            try? ctx.save()
        }
        // If not connected, they remain dirty for next sync
    }

    private func fetchDirtyEntities<T: PersistentModel>(_ type: T.Type, context: ModelContext) throws -> [T] {
        let descriptor = FetchDescriptor<T>()
        let all = try context.fetch(descriptor)
        // Use runtime check for isDirty property since PersistentModel doesn't declare it
        return all.filter { entity in
            if let todo = entity as? Todo { return todo.isDirty }
            if let project = entity as? Project { return project.isDirty }
            if let area = entity as? Area { return area.isDirty }
            if let tag = entity as? Tag { return tag.isDirty }
            return false
        }
    }

    private func markEntitiesClean(todos: [Todo], projects: [Project], areas: [Area], tags: [Tag]) {
        for todo in todos {
            todo.isDirty = false
            todo.lastSyncedAt = Date()
            if todo.syncId == nil { todo.syncId = todo.id.uuidString }
        }
        for project in projects {
            project.isDirty = false
            project.lastSyncedAt = Date()
            if project.syncId == nil { project.syncId = project.id.uuidString }
        }
        for area in areas {
            area.isDirty = false
            if area.syncId == nil { area.syncId = area.id.uuidString }
        }
        for tag in tags {
            tag.isDirty = false
            if tag.syncId == nil { tag.syncId = tag.id.uuidString }
        }
    }

    // MARK: - Pull via HTTP (fallback when WebSocket is not connected)

    private func pullViaHTTP() async throws {
        // Fetch all todos from server and reconcile
        let todosResponse = try await apiClient.fetchTodos(page: 1, limit: 500)
        for dto in todosResponse.data {
            applyTodoDTO(dto)
        }

        let projectsResponse = try await apiClient.fetchProjects(page: 1, limit: 500)
        for dto in projectsResponse.data {
            applyProjectDTO(dto)
        }

        let areasResponse = try await apiClient.fetchAreas(page: 1, limit: 500)
        for dto in areasResponse.data {
            applyAreaDTO(dto)
        }

        let tagsResponse = try await apiClient.fetchTags(page: 1, limit: 500)
        for dto in tagsResponse.data {
            applyTagDTO(dto)
        }

        try? modelContext?.save()
    }

    // MARK: - Apply Remote Changes

    private func applyRemoteChanges(_ entries: [SyncLogEntry]) {
        guard let ctx = modelContext else { return }

        for entry in entries {
            switch entry.entityType {
            case "todo":
                applyTodoChange(entry)
            case "project":
                applyProjectChange(entry)
            case "area":
                applyAreaChange(entry)
            case "tag":
                applyTagChange(entry)
            default:
                break
            }
        }

        try? ctx.save()
    }

    // MARK: - Apply Individual Entity Changes

    private func applyTodoChange(_ entry: SyncLogEntry) {
        guard let ctx = modelContext else { return }

        if entry.action == "delete" {
            if let existing = findTodo(id: entry.entityId, in: ctx) {
                ctx.delete(existing)
            }
            return
        }

        guard let payload = entry.payload else { return }

        if let existing = findTodo(id: entry.entityId, in: ctx) {
            // Last-writer-wins: server wins
            if !existing.isDirty {
                updateTodoFromPayload(existing, payload: payload)
            }
        } else if entry.action == "create" {
            let todo = Todo(title: payload["title"]?.stringValue ?? "Untitled")
            if let uuid = UUID(uuidString: entry.entityId) {
                todo.id = uuid
            }
            updateTodoFromPayload(todo, payload: payload)
            todo.isDirty = false
            todo.syncId = entry.entityId
            ctx.insert(todo)
        }
    }

    private func applyProjectChange(_ entry: SyncLogEntry) {
        guard let ctx = modelContext else { return }

        if entry.action == "delete" {
            if let existing = findProject(id: entry.entityId, in: ctx) {
                ctx.delete(existing)
            }
            return
        }

        guard let payload = entry.payload else { return }

        if let existing = findProject(id: entry.entityId, in: ctx) {
            if !existing.isDirty {
                updateProjectFromPayload(existing, payload: payload)
            }
        } else if entry.action == "create" {
            let project = Project(title: payload["title"]?.stringValue ?? "Untitled")
            if let uuid = UUID(uuidString: entry.entityId) {
                project.id = uuid
            }
            updateProjectFromPayload(project, payload: payload)
            project.isDirty = false
            project.syncId = entry.entityId
            ctx.insert(project)
        }
    }

    private func applyAreaChange(_ entry: SyncLogEntry) {
        guard let ctx = modelContext else { return }

        if entry.action == "delete" {
            if let existing = findArea(id: entry.entityId, in: ctx) {
                ctx.delete(existing)
            }
            return
        }

        guard let payload = entry.payload else { return }

        if let existing = findArea(id: entry.entityId, in: ctx) {
            if !existing.isDirty {
                updateAreaFromPayload(existing, payload: payload)
            }
        } else if entry.action == "create" {
            let area = Area(title: payload["title"]?.stringValue ?? "Untitled")
            if let uuid = UUID(uuidString: entry.entityId) {
                area.id = uuid
            }
            updateAreaFromPayload(area, payload: payload)
            area.isDirty = false
            area.syncId = entry.entityId
            ctx.insert(area)
        }
    }

    private func applyTagChange(_ entry: SyncLogEntry) {
        guard let ctx = modelContext else { return }

        if entry.action == "delete" {
            if let existing = findTag(id: entry.entityId, in: ctx) {
                ctx.delete(existing)
            }
            return
        }

        guard let payload = entry.payload else { return }

        if let existing = findTag(id: entry.entityId, in: ctx) {
            if !existing.isDirty {
                updateTagFromPayload(existing, payload: payload)
            }
        } else if entry.action == "create" {
            let tag = Tag(title: payload["title"]?.stringValue ?? "Untitled")
            if let uuid = UUID(uuidString: entry.entityId) {
                tag.id = uuid
            }
            updateTagFromPayload(tag, payload: payload)
            tag.isDirty = false
            tag.syncId = entry.entityId
            ctx.insert(tag)
        }
    }

    // MARK: - Apply DTOs from HTTP pull

    private func applyTodoDTO(_ dto: TodoDTO) {
        guard let ctx = modelContext else { return }
        guard let uuid = UUID(uuidString: dto.id) else { return }

        if let existing = findTodo(id: dto.id, in: ctx) {
            if !existing.isDirty {
                existing.title = dto.title
                existing.notes = dto.notes ?? ""
                if let status = TodoStatus(rawValue: dto.status) { existing.status = status }
                if let priority = Priority(rawValue: dto.priority) { existing.priority = priority }
                existing.sortOrder = dto.sortOrder
                existing.scheduledDate = parseDate(dto.scheduledDate)
                existing.deadline = parseDate(dto.deadline)
                existing.completedAt = parseDate(dto.completedAt)
                existing.syncId = dto.id
                existing.isDirty = false
                existing.lastSyncedAt = Date()
            }
        } else {
            let todo = Todo(title: dto.title)
            todo.id = uuid
            todo.notes = dto.notes ?? ""
            if let status = TodoStatus(rawValue: dto.status) { todo.status = status }
            if let priority = Priority(rawValue: dto.priority) { todo.priority = priority }
            todo.sortOrder = dto.sortOrder
            todo.scheduledDate = parseDate(dto.scheduledDate)
            todo.deadline = parseDate(dto.deadline)
            todo.completedAt = parseDate(dto.completedAt)
            todo.syncId = dto.id
            todo.isDirty = false
            todo.lastSyncedAt = Date()
            ctx.insert(todo)
        }
    }

    private func applyProjectDTO(_ dto: ProjectDTO) {
        guard let ctx = modelContext else { return }
        guard let uuid = UUID(uuidString: dto.id) else { return }

        if let existing = findProject(id: dto.id, in: ctx) {
            if !existing.isDirty {
                existing.title = dto.title
                existing.notes = dto.notes ?? ""
                if let status = ProjectStatus(rawValue: dto.status) { existing.status = status }
                existing.sortOrder = dto.sortOrder
                existing.deadline = parseDate(dto.deadline)
                existing.syncId = dto.id
                existing.isDirty = false
                existing.lastSyncedAt = Date()
            }
        } else {
            let project = Project(title: dto.title)
            project.id = uuid
            project.notes = dto.notes ?? ""
            if let status = ProjectStatus(rawValue: dto.status) { project.status = status }
            project.sortOrder = dto.sortOrder
            project.deadline = parseDate(dto.deadline)
            project.syncId = dto.id
            project.isDirty = false
            project.lastSyncedAt = Date()
            ctx.insert(project)
        }
    }

    private func applyAreaDTO(_ dto: AreaDTO) {
        guard let ctx = modelContext else { return }
        guard let uuid = UUID(uuidString: dto.id) else { return }

        if let existing = findArea(id: dto.id, in: ctx) {
            if !existing.isDirty {
                existing.title = dto.title
                existing.sortOrder = dto.sortOrder
                existing.syncId = dto.id
                existing.isDirty = false
            }
        } else {
            let area = Area(title: dto.title)
            area.id = uuid
            area.sortOrder = dto.sortOrder
            area.syncId = dto.id
            area.isDirty = false
            ctx.insert(area)
        }
    }

    private func applyTagDTO(_ dto: TagDTO) {
        guard let ctx = modelContext else { return }
        guard let uuid = UUID(uuidString: dto.id) else { return }

        if let existing = findTag(id: dto.id, in: ctx) {
            if !existing.isDirty {
                existing.title = dto.title
                existing.color = dto.color
                existing.sortOrder = dto.sortOrder
                existing.syncId = dto.id
                existing.isDirty = false
            }
        } else {
            let tag = Tag(title: dto.title, color: dto.color)
            tag.id = uuid
            tag.sortOrder = dto.sortOrder
            tag.syncId = dto.id
            tag.isDirty = false
            ctx.insert(tag)
        }
    }

    // MARK: - Helpers

    private func findTodo(id: String, in context: ModelContext) -> Todo? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        let descriptor = FetchDescriptor<Todo>(predicate: #Predicate { $0.id == uuid })
        return try? context.fetch(descriptor).first
    }

    private func findProject(id: String, in context: ModelContext) -> Project? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == uuid })
        return try? context.fetch(descriptor).first
    }

    private func findArea(id: String, in context: ModelContext) -> Area? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        let descriptor = FetchDescriptor<Area>(predicate: #Predicate { $0.id == uuid })
        return try? context.fetch(descriptor).first
    }

    private func findTag(id: String, in context: ModelContext) -> Tag? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        let descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.id == uuid })
        return try? context.fetch(descriptor).first
    }

    private func updateTodoFromPayload(_ todo: Todo, payload: [String: AnyCodableValue]) {
        if let title = payload["title"]?.stringValue { todo.title = title }
        if let notes = payload["notes"]?.stringValue { todo.notes = notes }
        if let statusStr = payload["status"]?.stringValue,
           let status = TodoStatus(rawValue: statusStr) { todo.status = status }
        if let priorityInt = payload["priority"]?.intValue,
           let priority = Priority(rawValue: priorityInt) { todo.priority = priority }
        if let sortOrder = payload["sortOrder"]?.intValue { todo.sortOrder = sortOrder }
        if let dateStr = payload["scheduledDate"]?.stringValue { todo.scheduledDate = parseDate(dateStr) }
        if let dateStr = payload["deadline"]?.stringValue { todo.deadline = parseDate(dateStr) }
        if let dateStr = payload["completedAt"]?.stringValue { todo.completedAt = parseDate(dateStr) }
        todo.lastSyncedAt = Date()
    }

    private func updateProjectFromPayload(_ project: Project, payload: [String: AnyCodableValue]) {
        if let title = payload["title"]?.stringValue { project.title = title }
        if let notes = payload["notes"]?.stringValue { project.notes = notes }
        if let statusStr = payload["status"]?.stringValue,
           let status = ProjectStatus(rawValue: statusStr) { project.status = status }
        if let sortOrder = payload["sortOrder"]?.intValue { project.sortOrder = sortOrder }
        if let dateStr = payload["deadline"]?.stringValue { project.deadline = parseDate(dateStr) }
        project.lastSyncedAt = Date()
    }

    private func updateAreaFromPayload(_ area: Area, payload: [String: AnyCodableValue]) {
        if let title = payload["title"]?.stringValue { area.title = title }
        if let sortOrder = payload["sortOrder"]?.intValue { area.sortOrder = sortOrder }
    }

    private func updateTagFromPayload(_ tag: Tag, payload: [String: AnyCodableValue]) {
        if let title = payload["title"]?.stringValue { tag.title = title }
        if let color = payload["color"]?.stringValue { tag.color = color }
        if let sortOrder = payload["sortOrder"]?.intValue { tag.sortOrder = sortOrder }
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
