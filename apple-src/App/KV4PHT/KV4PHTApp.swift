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
            .commands {
                CommandGroup(replacing: .appInfo) { AboutCommand() }
            }
        #endif
        #if os(macOS)
            Window("About kv4p HT", id: AboutCommand.window) { AboutView() }
                .windowResizability(.contentSize)
        #endif
    }
}

#if os(macOS)
    /// "About kv4p HT" in the app menu opens the About window instead of the standard panel.
    private struct AboutCommand: View {
        static let window = "about"
        @Environment(\.openWindow) private var openWindow

        var body: some View {
            Button("About kv4p HT") { openWindow(id: Self.window) }
        }
    }
#endif
