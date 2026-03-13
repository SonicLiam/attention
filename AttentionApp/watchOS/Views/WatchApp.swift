import SwiftUI
import SwiftData

@main
struct AttentionWatchApp: App {
    let container: ModelContainer

    init() {
        container = DataContainer.create()
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .modelContainer(container)
        }
    }
}
