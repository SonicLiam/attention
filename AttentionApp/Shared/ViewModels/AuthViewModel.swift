import Foundation

@MainActor
@Observable
final class AuthViewModel {
    var isAuthenticated = false
    var isLoading = false
    var errorMessage: String?
    var currentUser: UserInfo?

    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
        Task {
            await restoreSession()
        }
    }

    // MARK: - Restore Session

    func restoreSession() async {
        let hasToken = await apiClient.isAuthenticated
        if hasToken {
            // Try refreshing to validate the session
            do {
                try await apiClient.refreshToken()
                isAuthenticated = true
            } catch {
                // Token is invalid, clear it
                await apiClient.logout()
                isAuthenticated = false
            }
        }
    }

    // MARK: - Login

    func login(email: String, password: String) async {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter email and password"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await apiClient.login(email: email, password: password)
            currentUser = response.user
            isAuthenticated = true
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Register

    func register(email: String, password: String, displayName: String) async {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter email and password"
            return
        }
        guard password.count >= 8 else {
            errorMessage = "Password must be at least 8 characters"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let name = displayName.isEmpty ? nil : displayName
            let response = try await apiClient.register(email: email, password: password, displayName: name)
            currentUser = response.user
            isAuthenticated = true
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Logout

    func logout() async {
        await apiClient.logout()
        currentUser = nil
        isAuthenticated = false
        UserDefaults.standard.set(0, forKey: "lastSyncId")
    }
}
