import KV4PRadio
import SwiftUI

/// The main window, structured like the Android app (ADR-0040): the header on top, the memories and APRS below, PTT
/// in reach and the settings on their own screen. With room for it, the memories and APRS stand side by side;
/// otherwise they and the settings are pages to swipe between.
struct RootView: View {
    let model: RadioViewModel
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
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
                CompactScreen(model: model)
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

#if os(iOS)
    /// iPhone and narrow iPad windows: one page each for the memories, APRS and the settings. The header and PTT stay
    /// outside the pages, so that a moving finger on PTT does not change the page and end the transmission.
    private struct CompactScreen: View {
        private enum Page: String, CaseIterable, Identifiable {
            case memories, aprs, settings

            var id: Self { self }

            var title: String {
                switch self {
                case .memories: "Memories"
                case .aprs: "APRS"
                case .settings: "Settings"
                }
            }

            var symbol: String {
                switch self {
                case .memories: "list.bullet"
                case .aprs: "point.3.connected.trianglepath.dotted"
                case .settings: "gearshape"
                }
            }
        }

        let model: RadioViewModel
        /// The page shown last, also after a restart.
        @AppStorage("mainPage") private var page = Page.memories

        var body: some View {
            VStack(spacing: 0) {
                if page != .settings {
                    RadioHeader(model: model)
                    Divider()
                }
                TabView(selection: $page) {
                    MemoriesView(model: model).tag(Page.memories)
                    APRSView(model: model).tag(Page.aprs)
                    NavigationStack { SettingsView(model: model) }.tag(Page.settings)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                if page == .memories {
                    Divider()
                    PTTBar(model: model)
                }
                NoticeBanner(model: model)
                pageBar
            }
        }

        private var pageBar: some View {
            HStack {
                ForEach(Page.allCases) { item in
                    Button {
                        withAnimation { page = item }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: item.symbol).font(.title3)
                            Text(item.title).font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .foregroundStyle(page == item ? Color.accentColor : Color.secondary)
                    .accessibilityAddTraits(page == item ? .isSelected : [])
                }
            }
            .padding(.top, 6)
            .background(.bar)
        }
    }
#endif
