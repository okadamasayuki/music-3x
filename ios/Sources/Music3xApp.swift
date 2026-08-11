import SwiftUI

@main
struct Music3xApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var player = PlayerEngine()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(player)
        }
    }
}
