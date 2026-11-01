import KV4PRadio
import SwiftUI

@main
struct KV4PHTApp: App {
    @State private var model = Composition.makeViewModel()

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                MemoriesView(model: model)
            } detail: {
                RadioView(model: model)
            }
        }
        #if os(macOS)
            .defaultSize(width: 900, height: 720)
        #endif
    }
}
