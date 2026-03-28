import SwiftUI

@main
struct AveroApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Avero") {
            ContentView(model: model)
                .frame(minWidth: 1080, minHeight: 720)
        }
    }
}
