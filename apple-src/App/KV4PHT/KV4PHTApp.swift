import KV4PRadio
import SwiftUI

@main
struct KV4PHTApp: App {
    @State private var model = Composition.makeViewModel()

    var body: some Scene {
        WindowGroup {
            RadioView(model: model)
        }
        #if os(macOS)
            .windowResizability(.contentSize)
        #endif
    }
}
