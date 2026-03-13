import SwiftUI
import SwiftData

@main
struct AttentionApp: App {
    let container: ModelContainer

    @State private var viewModel = TodoListViewModel()
    @State private var authViewModel = AuthViewModel()
    @State private var webSocketClient = WebSocketClient()
    @State private var syncEngine: SyncEngine

    init() {
        container = DataContainer.create()
        let ws = WebSocketClient()
        _webSocketClient = State(initialValue: ws)
        _syncEngine = State(initialValue: SyncEngine(webSocketClient: ws))
    }

    var body: some Scene {
        #if os(macOS)
        Window("Attention", id: "main") {
            Group {
                if authViewModel.isAuthenticated {
                    MacContentView()
                        .environment(viewModel)
                        .environment(syncEngine)
                } else {
                    AuthView()
                }
            }
            .environment(authViewModel)
            .modelContainer(container)
            .task {
                _ = await NotificationService.shared.requestAuthorization()
            }
            .task(id: authViewModel.isAuthenticated) {
                if authViewModel.isAuthenticated {
                    syncEngine.configure(modelContext: container.mainContext)
                    await syncEngine.connectWebSocket()
                    await syncEngine.performSync()
                } else {
                    syncEngine.disconnectWebSocket()
                }
            }
        }
        .defaultSize(width: 1100, height: 700)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        #else
        WindowGroup {
            Group {
                if authViewModel.isAuthenticated {
                    iOSContentView()
                        .environment(viewModel)
                        .environment(syncEngine)
                } else {
                    iOSAuthView()
                }
            }
            .environment(authViewModel)
            .modelContainer(container)
            .task {
                _ = await NotificationService.shared.requestAuthorization()
            }
            .task(id: authViewModel.isAuthenticated) {
                if authViewModel.isAuthenticated {
                    syncEngine.configure(modelContext: container.mainContext)
                    await syncEngine.connectWebSocket()
                    await syncEngine.performSync()
                } else {
                    syncEngine.disconnectWebSocket()
                }
            }
        }
        #endif
    }
}
