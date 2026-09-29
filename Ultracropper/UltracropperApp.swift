import SwiftUI

@main
struct UltracropperApp: App {
    var body: some Scene {
        WindowGroup("Ultracropper") {
            ContentView()
        }
        .defaultSize(width: 900, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
