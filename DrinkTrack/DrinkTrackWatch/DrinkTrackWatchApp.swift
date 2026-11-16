import SwiftUI

@main
struct DrinkTrackWatchApp: App {
    @StateObject private var store = WatchSessionStore.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(store)
        }
    }
}
