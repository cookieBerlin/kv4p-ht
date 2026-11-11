import KV4PRadio
import SwiftUI

/// The main window, structured like the Android app (ADR-0040): the header on top, the memories and APRS below, PTT
/// in reach and the settings on their own screen. With room for it, the memories and APRS stand side by side;
/// otherwise they and the settings are pages to swipe between.
struct RootView: View {
    let model: RadioViewModel
    @State private var isReporting = false
    #if os(iOS)
        /// The settings opened on a wide iPad, and the pages within them.
        @State private var settingsPath: [SettingsDestination] = []
    #endif
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
            .task {
                await model.loadMemories()
                await model.connectAtStart()
            }
            .sheet(isPresented: .constant(model.isStationSetupPending)) { StationSetupView(model: model) }
    }

    @ViewBuilder private var content: some View {
        #if os(iOS)
            if sizeClass == .compact {
                CompactScreen(model: model)
            } else {
                NavigationStack(path: $settingsPath) {
                    sideBySide.mainChrome(model, title: "kv4p HT", settingsPath: $settingsPath)
                        .settingsDestinations(model)
                }
            }
        #else
            sideBySide.mainChrome(model, title: "kv4p HT").frame(minWidth: 700, minHeight: 600)
        #endif
    }

    /// Without APRS, the memories take the whole width.
    private var sideBySide: some View {
        HStack(spacing: 0) {
            if model.isAPRSEnabled {
                MemoriesView(model: model).frame(minWidth: 280, maxWidth: 400)
                Divider()
                APRSView(model: model).frame(minWidth: 320)
            } else {
                MemoriesView(model: model).frame(minWidth: 280)
            }
        }
    }
}

#if os(iOS)
    /// iPhone and narrow iPad windows: one page each for the memories, the APRS packets, the chats and the settings, in a
    /// ring, so that a swipe goes from the memories straight to the settings and back. The header and PTT stay outside
    /// the pages, so that a moving finger on PTT does not change the page and end the transmission.
    private struct CompactScreen: View {
        private enum Page: String, CaseIterable, Identifiable {
            case memories, packets, chats, settings

            var id: Self { self }

            var title: String {
                switch self {
                case .memories: "Memories"
                case .packets: "Packets"
                case .chats: "Chats"
                case .settings: "Settings"
                }
            }

            var symbol: String {
                switch self {
                case .memories: "list.bullet"
                case .packets: "point.3.connected.trianglepath.dotted"
                case .chats: "bubble.left.and.bubble.right"
                case .settings: "gearshape"
                }
            }

            /// What the APRS page of a wider screen would show.
            var aprsPage: APRSPage? {
                switch self {
                case .packets: .packets
                case .chats: .chats
                case .memories, .settings: nil
                }
            }
        }

        /// A place in the row of pages: a scroll view does not close into a ring, so a copy of the last page stands
        /// before the first and a copy of the first after the last; a swipe that ends on a copy jumps to the page.
        private enum Slot: Hashable {
            case page(Page)
            case copyBefore, copyAfter

            var page: Page {
                switch self {
                case .page(let page): page
                case .copyBefore: .settings
                case .copyAfter: .memories
                }
            }
        }

        let model: RadioViewModel
        /// The page shown last, also after a restart.
        @AppStorage("mainPage") private var page = Page.memories
        /// Where the scroll view stands, which follows `page` and leads it when swiped.
        @State private var shownSlot: Slot?
        /// The bars below the pages make way for the keyboard, so that the line to write stays above it.
        @State private var isKeyboardShown = false
        /// The pages opened in the settings. While one is open, a swipe goes back to the list rather than to another page.
        @State private var settingsPath: [SettingsDestination] = []
        @Environment(\.scenePhase) private var scenePhase

        /// One page over the full width; all are there at once, so each is told whether it is the one shown.
        private func pageView(_ item: Page, @ViewBuilder content: () -> some View) -> some View {
            content()
                // Scrolling within a page stays, also while the pages do not move.
                .environment(\.isScrollEnabled, true)
                .containerRelativeFrame(.horizontal)
                .environment(\.isPageOnScreen, page == item)
                .id(Slot.page(item))
        }

        /// A copy shows the page while a swipe passes it; it is there to look at only.
        private func copyView(_ slot: Slot, @ViewBuilder content: () -> some View) -> some View {
            content()
                .containerRelativeFrame(.horizontal)
                .environment(\.isPageOnScreen, false)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .id(slot)
        }

        var body: some View {
            VStack(spacing: 0) {
                if page != .settings {
                    RadioHeader(model: model)
                    Divider()
                }
                // A scroll view rather than a paged `TabView`: that one wraps each page in a controller of its own, and
                // UIKit stops the app when the navigation stack of the settings sits in one while a page changes.
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        copyView(.copyBefore) { NavigationStack { SettingsView(model: model) } }
                        pageView(.memories) { MemoriesView(model: model) }
                        if model.isAPRSEnabled {
                            pageView(.packets) { APRSView(model: model, page: .packets) }
                            pageView(.chats) { APRSView(model: model, page: .chats) }
                        }
                        pageView(.settings) {
                            NavigationStack(path: $settingsPath) {
                                SettingsView(model: model).settingsDestinations(model)
                            }
                        }
                        copyView(.copyAfter) { MemoriesView(model: model) }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                // On a page of the settings, a swipe goes back to their list.
                .scrollDisabled(page == .settings && !settingsPath.isEmpty)
                .scrollPosition(id: $shownSlot)
                .onAppear {
                    showMemoriesIfHidden()
                    shownSlot = .page(page)
                }
                .onChange(of: model.isAPRSEnabled) {
                    showMemoriesIfHidden()
                    // The pages before it come or go, and the scroll view stays where it was, on another page. Once
                    // they are laid out, it goes back to the page; unset first, as the same value moves nothing.
                    shownSlot = nil
                    Task {
                        var jump = Transaction()
                        jump.disablesAnimations = true
                        withTransaction(jump) { shownSlot = .page(page) }
                    }
                }
                .onChange(of: shownSlot) {
                    if let shownSlot, shownSlot.page != page { page = shownSlot.page }
                }
                .onChange(of: page) {
                    if shownSlot?.page != page { withAnimation { shownSlot = .page(page) } }
                }
                .onScrollPhaseChange { _, phase in
                    if phase == .idle, let shownSlot, shownSlot != .page(shownSlot.page) {
                        var jump = Transaction()
                        jump.disablesAnimations = true
                        withTransaction(jump) { self.shownSlot = .page(shownSlot.page) }
                    }
                }
                .onChange(of: model.aprsReplyCount) { withAnimation { page = .packets } }
                .onChange(of: model.chatRequestCount) { withAnimation { page = .chats } }
                // A message of a chat in the packets opens the chat.
                .onChange(of: model.aprsPage) {
                    if page.aprsPage != nil, model.aprsPage == .chats { withAnimation { page = .chats } }
                }
                .onChange(of: page, initial: true) {
                    if let aprsPage = page.aprsPage { model.aprsPage = aprsPage }
                    updateAPRSVisibility()
                }
                .onChange(of: scenePhase) { updateAPRSVisibility() }
                // A text field on a page that is swiped away keeps the keyboard otherwise, with no way to close it.
                .onChange(of: page) { dismissKeyboard() }
                if !isKeyboardShown {
                    if page == .settings {
                        // The settings show the state of the connection themselves.
                        NoticeBanner(model: model)
                    } else {
                        BottomBar(model: model, showsPTT: page == .memories) {
                            withAnimation { page = .settings }
                        }
                    }
                    pageBar
                }
            }
            .observesKeyboard($isKeyboardShown)
        }

        /// The pages there are: without APRS, its two go.
        private var pages: [Page] {
            Page.allCases.filter { $0.aprsPage == nil || model.isAPRSEnabled }
        }

        /// The page shown last may be one that went since; the app then starts with the memories.
        private func showMemoriesIfHidden() {
            if !pages.contains(page) { page = .memories }
        }

        /// For the chats to count as read and the list to show distances while one of them is on screen.
        private func updateAPRSVisibility() {
            model.isAPRSVisible = page.aprsPage != nil && scenePhase == .active
        }

        /// The number of new messages in the chats (ADR-0058).
        private var newMessages: some View {
            CountBadge(count: model.newAPRSMessages, color: .red)
                .fixedSize()
                .offset(x: 10, y: -6)
        }

        private var pageBar: some View {
            HStack {
                ForEach(pages) { item in
                    Button {
                        withAnimation { page = item }
                    } label: {
                        Image(systemName: item.symbol)
                            .font(.title)
                            .imageScale(.large)
                            .overlay(alignment: .topTrailing) {
                                if item == .chats, model.newAPRSMessages > 0 {
                                    newMessages
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(.rect)
                    }
                    // The symbols are large already and keep their size; a long press shows a page large instead.
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .accessibilityLabel(item.title)
                    .accessibilityShowsLargeContentViewer { Label(item.title, systemImage: item.symbol) }
                    .accessibilityValue(
                        item == .chats && model.newAPRSMessages > 0 ? "\(model.newAPRSMessages) new" : ""
                    )
                    .foregroundStyle(page == item ? Color.accentColor : Color.secondary)
                    .accessibilityAddTraits(page == item ? .isSelected : [])
                    // For the UI tests, as the pages are all there at once and share names with links (ADR-0062).
                    .accessibilityIdentifier("page-\(item.title)")
                }
            }
            .padding(.top, 4)
            .background(Color.opaqueBar)
        }
    }
#endif

extension EnvironmentValues {
    /// Whether the page that holds a view is the one shown, where pages sit side by side; elsewhere always.
    @Entry var isPageOnScreen = true
}
