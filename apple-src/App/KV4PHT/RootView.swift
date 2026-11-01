import KV4PRadio
import SwiftUI

/// The main window. The Mac shows the memories in a sidebar next to the radio and APRS. iPhone and iPad show one tab
/// each, with the radio first: at the bottom on the iPhone, at the top or as a sidebar on the iPad.
struct RootView: View {
    let model: RadioViewModel
    #if os(iOS)
        /// The tab shown last, also after a restart.
        @AppStorage("selectedTab") private var selectedTab = "radio"
    #endif

    var body: some View {
        #if os(iOS)
            TabView(selection: $selectedTab) {
                Tab("Radio", systemImage: "dot.radiowaves.left.and.right", value: "radio") {
                    NavigationStack { RadioView(model: model) }
                }
                Tab("Memories", systemImage: "list.bullet", value: "memories") {
                    NavigationStack { MemoriesView(model: model).pttBar(model) }
                }
                Tab("APRS", systemImage: "point.3.connected.trianglepath.dotted", value: "aprs") {
                    NavigationStack { APRSView(model: model) }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
        #else
            NavigationSplitView {
                MemoriesView(model: model)
            } detail: {
                TabView {
                    Tab("Radio", systemImage: "dot.radiowaves.left.and.right") { RadioView(model: model) }
                    Tab("APRS", systemImage: "point.3.connected.trianglepath.dotted") { APRSView(model: model) }
                }
            }
        #endif
    }
}
