import KV4PRadio
import SwiftUI

/// The main window, structured like the Android app (ADR-0040): the header on top, the memories and APRS below, PTT
/// in reach and the settings on their own screen. With room for it, the memories and APRS stand side by side;
/// otherwise each has a tab.
struct RootView: View {
    let model: RadioViewModel
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
        /// The tab shown last, also after a restart.
        @AppStorage("mainTab") private var selectedTab = "memories"
    #endif

    var body: some View {
        content
            .alert(
                "Radio problem",
                isPresented: Binding(
                    get: { model.alertMessage != nil },
                    set: { if !$0 { model.dismissAlert() } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.alertMessage ?? "")
            }
            .onAppear { model.refreshConnections() }
            .onChange(of: scenePhase, initial: true) {
                model.isInBackground = scenePhase == .background
                if scenePhase == .active { model.startBluetoothScan() } else { model.stopBluetoothScan() }
            }
            .task { await model.loadMemories() }
    }

    @ViewBuilder private var content: some View {
        #if os(iOS)
            if sizeClass == .compact {
                TabView(selection: $selectedTab) {
                    Tab("Memories", systemImage: "list.bullet", value: "memories") {
                        NavigationStack { MemoriesView(model: model).mainChrome(model, title: "Memories") }
                    }
                    Tab("APRS", systemImage: "point.3.connected.trianglepath.dotted", value: "aprs") {
                        NavigationStack { APRSView(model: model).mainChrome(model, title: "APRS") }
                    }
                }
            } else {
                NavigationStack { sideBySide.mainChrome(model, title: "kv4p HT") }
            }
        #else
            sideBySide.mainChrome(model, title: "kv4p HT").frame(minWidth: 700, minHeight: 600)
        #endif
    }

    private var sideBySide: some View {
        HStack(spacing: 0) {
            MemoriesView(model: model).frame(minWidth: 280, maxWidth: 400)
            Divider()
            APRSView(model: model).frame(minWidth: 320)
        }
    }
}
