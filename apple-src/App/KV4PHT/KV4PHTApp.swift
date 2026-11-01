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
                TabView {
                    Tab("Radio", systemImage: "dot.radiowaves.left.and.right") { RadioView(model: model) }
                    Tab("APRS", systemImage: "point.3.connected.trianglepath.dotted") { APRSView(model: model) }
                }
            }
        }
        #if os(macOS)
            .defaultSize(width: 900, height: 720)
        #endif
    }
}
