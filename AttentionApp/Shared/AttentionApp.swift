import SwiftUI
import SwiftData

@main
struct AttentionApp: App {
    let container: ModelContainer

    @State private var viewModel = TodoListViewModel()

    init() {
        container = DataContainer.create()
    }

    var body: some Scene {
        #if os(macOS)
        Window("Attention", id: "main") {
            MacContentView()
                .environment(viewModel)
                .modelContainer(container)
        }
        .defaultSize(width: 1100, height: 700)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        #else
        WindowGroup {
            iOSContentView()
                .environment(viewModel)
                .modelContainer(container)
        }
        #endif
    }
}
