import SwiftUI

@main
struct MagLEDApp: App {
    @StateObject private var model = Model()

    var body: some Scene {
        WindowGroup("MagLED") {
            ContentView().environmentObject(model)
        }
        MenuBarExtra("MagLED", systemImage: "bolt.fill") {
            Button("Restore system LED") { model.restoreLED() }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}
