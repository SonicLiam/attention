import Foundation

// MARK: - API Error

enum APIError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case decodingError(Error)
    case encodingError(Error)
    case networkError(Error)
    case unauthorized
    case tokenRefreshFailed
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unauthorized:
            return "Authentication required"
        case .tokenRefreshFailed:
            return "Session expired. Please log in again."
        case .unknown:
            return "An unknown error occurred"
        }
    }
}

// MARK: - API Response Types

struct AuthResponse: Codable, Sendable {
    let user: UserInfo
    let accessToken: String
    let refreshToken: String
}

struct UserInfo: Codable, Sendable {
    let id: String
    let email: String
    let displayName: String?
}

struct RefreshResponse: Codable, Sendable {
    let user: UserInfo
    let accessToken: String
    let refreshToken: String
}

struct ErrorResponse: Codable, Sendable {
    let error: String
}

struct PaginatedResponse<T: Codable & Sendable>: Codable, Sendable {
    let data: [T]
    let pagination: PaginationInfo
}

struct PaginationInfo: Codable, Sendable {
    let page: Int
    let limit: Int
    let total: Int
}

struct CreateResponse: Codable, Sendable {
    let id: String
    let message: String
}

struct UpdateResponse: Codable, Sendable {
    let id: String
    let message: String
    let version: Int?
}

struct DeleteResponse: Codable, Sendable {
    let message: String
}

// MARK: - Server DTOs

struct TodoDTO: Codable, Sendable {
    let id: String
    let title: String
    let notes: String?
    let status: String
    let priority: Int
    let createdAt: String?
    let updatedAt: String?
    let completedAt: String?
    let scheduledDate: String?
    let deadline: String?
    let sortOrder: Int
    let headingId: String?
    let projectId: String?
    let areaId: String?
    let version: Int?
    let tags: [TagRefDTO]?
    let checklist: [ChecklistItemDTO]?
}

struct TagRefDTO: Codable, Sendable {
    let id: String
    let title: String
    let color: String?
}

struct ChecklistItemDTO: Codable, Sendable {
    let id: String
    let title: String
    let isCompleted: Bool
    let sortOrder: Int
}

struct ProjectDTO: Codable, Sendable {
    let id: String
    let title: String
    let notes: String?
    let status: String
    let deadline: String?
    let sortOrder: Int
    let areaId: String?
    let version: Int?
}

struct AreaDTO: Codable, Sendable {
    let id: String
    let title: String
    let sortOrder: Int
    let version: Int?
}

struct TagDTO: Codable, Sendable {
    let id: String
    let title: String
    let color: String
    let sortOrder: Int
    let parentTagId: String?
    let version: Int?
}

// MARK: - Create/Update request bodies

struct CreateTodoBody: Codable, Sendable {
    let id: String?
    let title: String
    let notes: String?
    let status: String?
    let priority: Int?
    let scheduledDate: String?
    let deadline: String?
    let sortOrder: Int?
    let headingId: String?
    let projectId: String?
    let areaId: String?
    let tagIds: [String]?
    let checklist: [ChecklistItemBody]?
}

struct ChecklistItemBody: Codable, Sendable {
    let id: String?
    let title: String
    let isCompleted: Bool
    let sortOrder: Int
}

struct CreateProjectBody: Codable, Sendable {
    let id: String?
    let title: String
    let notes: String?
    let status: String?
    let deadline: String?
    let sortOrder: Int?
    let areaId: String?
}

struct CreateAreaBody: Codable, Sendable {
    let id: String?
    let title: String
    let sortOrder: Int?
}

struct CreateTagBody: Codable, Sendable {
    let id: String?
    let title: String
    let color: String?
    let sortOrder: Int?
    let parentTagId: String?
}

// MARK: - API Client

actor APIClient {
    static let shared = APIClient()

    private let baseURL: String
    private let session: URLSession
    private let keychain = KeychainHelper.shared
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var isRefreshing = false

    init(baseURL: String = "http://118.196.142.21") {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    // MARK: - Token Management

    var accessToken: String? {
        keychain.read(.accessToken)
    }

    var refreshTokenValue: String? {
        keychain.read(.refreshToken)
    }

    var isAuthenticated: Bool {
        keychain.read(.accessToken) != nil
    }

    func storeTokens(accessToken: String, refreshToken: String, userId: String) {
        keychain.save(accessToken, for: .accessToken)
        keychain.save(refreshToken, for: .refreshToken)
        keychain.save(userId, for: .userId)
    }

    func clearTokens() {
        keychain.deleteAll()
    }

    // MARK: - Generic Request

    private func makeRequest<T: Codable & Sendable>(
        method: String,
        path: String,
        body: (any Codable & Sendable)? = nil,
        queryItems: [URLQueryItem]? = nil,
        authenticated: Bool = true,
        retryOnUnauthorized: Bool = true
    ) async throws -> T {
        guard var urlComponents = URLComponents(string: "\(baseURL)/api/v1\(path)") else {
            throw APIError.invalidURL
        }

        if let queryItems, !queryItems.isEmpty {
            urlComponents.queryItems = queryItems
        }

        guard let url = urlComponents.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authenticated, let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            do {
                request.httpBody = try encoder.encode(body)
            } catch {
                throw APIError.encodingError(error)
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 && authenticated && retryOnUnauthorized {
            // Try refreshing token
            try await refreshToken()
            return try await makeRequest(
                method: method,
                path: path,
                body: body,
                queryItems: queryItems,
                authenticated: true,
                retryOnUnauthorized: false
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage: String
            if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
                errorMessage = errorResponse.error
            } else {
                errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            }
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Auth Endpoints

    func register(email: String, password: String, displayName: String?) async throws -> AuthResponse {
        struct RegisterBody: Codable, Sendable {
            let email: String
            let password: String
            let displayName: String?
        }
        let body = RegisterBody(email: email, password: password, displayName: displayName)
        let response: AuthResponse = try await makeRequest(
            method: "POST", path: "/auth/register", body: body, authenticated: false
        )
        storeTokens(accessToken: response.accessToken, refreshToken: response.refreshToken, userId: response.user.id)
        return response
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        struct LoginBody: Codable, Sendable {
            let email: String
            let password: String
        }
        let body = LoginBody(email: email, password: password)
        let response: AuthResponse = try await makeRequest(
            method: "POST", path: "/auth/login", body: body, authenticated: false
        )
        storeTokens(accessToken: response.accessToken, refreshToken: response.refreshToken, userId: response.user.id)
        return response
    }

    func refreshToken() async throws {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let currentRefreshToken = refreshTokenValue else {
            throw APIError.tokenRefreshFailed
        }

        struct RefreshBody: Codable, Sendable {
            let refreshToken: String
        }
        let body = RefreshBody(refreshToken: currentRefreshToken)

        let response: RefreshResponse
        do {
            response = try await makeRequest(
                method: "POST", path: "/auth/refresh", body: body,
                authenticated: false, retryOnUnauthorized: false
            )
        } catch {
            clearTokens()
            throw APIError.tokenRefreshFailed
        }

        storeTokens(accessToken: response.accessToken, refreshToken: response.refreshToken, userId: response.user.id)
    }

    func logout() {
        clearTokens()
    }

    // MARK: - Todo CRUD

    func fetchTodos(page: Int = 1, limit: Int = 50, status: String? = nil, projectId: String? = nil) async throws -> PaginatedResponse<TodoDTO> {
        var queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        if let status { queryItems.append(URLQueryItem(name: "status", value: status)) }
        if let projectId { queryItems.append(URLQueryItem(name: "projectId", value: projectId)) }

        return try await makeRequest(method: "GET", path: "/todos", queryItems: queryItems)
    }

    func fetchTodo(id: String) async throws -> TodoDTO {
        try await makeRequest(method: "GET", path: "/todos/\(id)")
    }

    func createTodo(_ body: CreateTodoBody) async throws -> CreateResponse {
        try await makeRequest(method: "POST", path: "/todos", body: body)
    }

    func updateTodo(id: String, _ body: CreateTodoBody) async throws -> UpdateResponse {
        try await makeRequest(method: "PUT", path: "/todos/\(id)", body: body)
    }

    func deleteTodo(id: String) async throws -> DeleteResponse {
        try await makeRequest(method: "DELETE", path: "/todos/\(id)")
    }

    // MARK: - Project CRUD

    func fetchProjects(page: Int = 1, limit: Int = 50) async throws -> PaginatedResponse<ProjectDTO> {
        let queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        return try await makeRequest(method: "GET", path: "/projects", queryItems: queryItems)
    }

    func createProject(_ body: CreateProjectBody) async throws -> CreateResponse {
        try await makeRequest(method: "POST", path: "/projects", body: body)
    }

    func updateProject(id: String, _ body: CreateProjectBody) async throws -> UpdateResponse {
        try await makeRequest(method: "PUT", path: "/projects/\(id)", body: body)
    }

    func deleteProject(id: String) async throws -> DeleteResponse {
        try await makeRequest(method: "DELETE", path: "/projects/\(id)")
    }

    // MARK: - Area CRUD

    func fetchAreas(page: Int = 1, limit: Int = 50) async throws -> PaginatedResponse<AreaDTO> {
        let queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        return try await makeRequest(method: "GET", path: "/areas", queryItems: queryItems)
    }

    func createArea(_ body: CreateAreaBody) async throws -> CreateResponse {
        try await makeRequest(method: "POST", path: "/areas", body: body)
    }

    func updateArea(id: String, _ body: CreateAreaBody) async throws -> UpdateResponse {
        try await makeRequest(method: "PUT", path: "/areas/\(id)", body: body)
    }

    func deleteArea(id: String) async throws -> DeleteResponse {
        try await makeRequest(method: "DELETE", path: "/areas/\(id)")
    }

    // MARK: - Tag CRUD

    func fetchTags(page: Int = 1, limit: Int = 50) async throws -> PaginatedResponse<TagDTO> {
        let queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        return try await makeRequest(method: "GET", path: "/tags", queryItems: queryItems)
    }

    func createTag(_ body: CreateTagBody) async throws -> CreateResponse {
        try await makeRequest(method: "POST", path: "/tags", body: body)
    }

    func updateTag(id: String, _ body: CreateTagBody) async throws -> UpdateResponse {
        try await makeRequest(method: "PUT", path: "/tags/\(id)", body: body)
    }

    func deleteTag(id: String) async throws -> DeleteResponse {
        try await makeRequest(method: "DELETE", path: "/tags/\(id)")
    }
}
