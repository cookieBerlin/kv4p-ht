import KV4PRadio
import SwiftUI

/// The main window, structured like the Android app (ADR-0040): the header on top, the memories and APRS below, PTT
/// in reach and the settings on their own screen. With room for it, the memories and APRS stand side by side;
/// otherwise they and the settings are pages to swipe between.
struct RootView: View {
    let model: RadioViewModel
    @State private var isReporting = false
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #else
        @Environment(\.openSettings) private var openSettings
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
                #if os(macOS)
                    if model.offersFirmwareSettings {
                        Button("Open Settings") {
                            model.requestFirmwareSettings()
                            openSettings()
                        }
                    }
                #endif
            } message: {
                Text(model.alertMessage ?? "")
            }
            .alert(
                "The app has crashed",
                isPresented: Binding(
                    get: { model.offersCrashReport },
                    set: { if !$0 { model.dismissCrashOffer() } }
                )
            ) {
                Button("Report…") { isReporting = true }
                Button("Not now", role: .cancel) {}
            } message: {
                Text("A report helps to find the cause. You see it first, and nothing is sent without you.")
            }
            .sheet(isPresented: $isReporting) { ProblemReportSheet(model: model) }
            .onAppear { model.refreshConnections() }
            .onChange(of: scenePhase, initial: true) {
                #if os(iOS)
                    model.isAppActive = scenePhase == .active
                #endif
                if scenePhase == .active {
                    model.refreshPermissions()  // the user may return from the system settings
                    model.startBluetoothScan()
                } else {
                    model.stopBluetoothScan()
                    model.flushSettingsSync()
                }
            }
            #if os(macOS)
                // The scene stays active behind another app here, where a window is still on screen.
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.isAppActive = true
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    model.isAppActive = false
                }
            #endif
            .task { await model.loadMemories() }
            .sheet(isPresented: .constant(model.isStationSetupPending)) { StationSetupView(model: model) }
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
                .onChange(of: model.aprsReplyCount) { withAnimation { page = .aprs } }
                .onChange(of: model.chatRequestCount) { withAnimation { page = .aprs } }
                if page == .settings {
                    if model.hasFailed {
                        StatusLine(model: model).padding(.vertical, 6)
                    }
                    NoticeBanner(model: model)
                } else {
                    BottomBar(model: model, showsPTT: page == .memories)
                }
                pageBar
            }
        }

        /// The number of new messages on the APRS page (ADR-0058).
        private var newMessages: some View {
            Text(model.newAPRSMessages, format: .number)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .background(.red, in: .capsule)
                .fixedSize()
                .offset(x: 10, y: -6)
        }

        private var pageBar: some View {
            HStack {
                ForEach(Page.allCases) { item in
                    Button {
                        withAnimation { page = item }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: item.symbol)
                                .font(.title3)
                                .overlay(alignment: .topTrailing) {
                                    if item == .aprs, model.newAPRSMessages > 0 {
                                        newMessages
                                    }
                                }
                            Text(item.title).font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .accessibilityValue(
                        item == .aprs && model.newAPRSMessages > 0 ? "\(model.newAPRSMessages) new" : ""
                    )
                    .foregroundStyle(page == item ? Color.accentColor : Color.secondary)
                    .accessibilityAddTraits(page == item ? .isSelected : [])
                }
            }
            .padding(.top, 6)
            .background(.bar)
        }
    }
#endif
