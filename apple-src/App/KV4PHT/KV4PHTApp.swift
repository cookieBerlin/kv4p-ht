import KV4PRadio
import SwiftUI

@main
struct KV4PHTApp: App {
    @State private var model = Composition.makeViewModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .defaultAppStorage(Composition.viewDefaults)
        }
        #if os(macOS)
            .defaultSize(width: 900, height: 720)
            .commands {
                CommandGroup(replacing: .appInfo) { AboutCommand() }
                CommandMenu("Radio") { RadioCommands(model: model) }
            }
        #endif
        #if os(macOS)
            Settings { SettingsView(model: model) }
            Window("About kv4p HT", id: AboutCommand.window) { AboutView() }
                .windowResizability(.contentSize)
        #endif
    }
}

#if os(macOS)
    /// The connection, and the keys that transmit, which the menu names so that they can be found (ADR-0075).
    private struct RadioCommands: View {
        let model: RadioViewModel

        var body: some View {
            Button(model.connectionAction.title) { Task { await model.runConnectionAction() } }
                .keyboardShortcut("k")
                .disabled(model.connectionAction == .connect && !model.canStartConnection)
            Divider()
            // A menu cannot tell when a key is let go; the window takes these keys itself.
            Button("Push to Talk: Hold Space") {}.disabled(true)
            Button("Access Tone: Hold ⌥ Space") {}.disabled(true)
        }
    }

    /// "About kv4p HT" in the app menu opens the About window instead of the standard panel.
    private struct AboutCommand: View {
        static let window = "about"
        @Environment(\.openWindow) private var openWindow

        var body: some View {
            Button("About kv4p HT") { openWindow(id: Self.window) }
        }
    }
#endif
