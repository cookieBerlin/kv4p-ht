import KV4PRadio
import SwiftUI

/// The main window, structured like the Android app (ADR-0040): the header on top, the memories and APRS below, PTT
/// in reach and the settings on their own screen. With room for it, the memories and APRS stand side by side;
/// otherwise they and the settings are pages to swipe between.
struct RootView: View {
    let model: RadioViewModel
    @State private var isReporting = false
    /// The section of this build, offered once after an update (ADR-0069).
    @State private var whatsNew: Changelog.Release?
    @State private var hasCheckedWhatsNew = false
    #if os(iOS)
        /// The settings opened and the pages within them, of both layouts: a foldable iPhone changes between them while
        /// the app runs, and the one that follows shows what the other showed (`handOver`).
        @State private var settingsPath: [SettingsDestination] = []
        @AppStorage(CompactPage.storageKey) private var compactPage = CompactPage.memories
        @AppStorage(SidePane.showsMapKey) private var sideShowsMap = false
    #endif
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #else
        @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        content
            .readsVerticalBarEdge()
            #if os(iOS)
                .onChange(of: sizeClass) { old, new in handOver(from: old, to: new) }
            #endif
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
            .sheet(
                isPresented: Binding(
                    get: { whatsNew != nil && !model.isStationSetupPending },
                    set: { if !$0 { whatsNew = nil } }
                )
            ) {
                if let whatsNew { WhatsNewView(release: whatsNew) }
            }
            .onAppear {
                // At the first start of a new build only; the station setup comes first.
                if !hasCheckedWhatsNew {
                    hasCheckedWhatsNew = true
                    whatsNew = BundledChangelog.offerAtStart(defaults: Composition.viewDefaults)
                }
            }
    }

    @ViewBuilder private var content: some View {
        #if os(iOS)
            if sizeClass == .compact {
                CompactScreen(model: model, settingsPath: $settingsPath)
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

    #if os(iOS)
        /// The layout that follows shows what the other showed: the settings that were open, and the page beside the
        /// memories. The wide layout puts the settings on top of the main screen, the compact one makes them a page.
        private func handOver(from old: UserInterfaceSizeClass?, to new: UserInterfaceSizeClass?) {
            if new == .compact, old != .compact {
                guard !settingsPath.isEmpty else {
                    // The settings were closed in the wide layout.
                    if compactPage == .settings { compactPage = .memories }
                    return
                }
                compactPage = .settings
                if settingsPath.first == .overview { settingsPath.removeFirst() }
            } else if new != .compact, old == .compact {
                switch compactPage {
                case .settings: settingsPath.insert(.overview, at: 0)
                case .map: sideShowsMap = true
                case .packets, .chats: sideShowsMap = false
                case .memories: break
                }
            }
        }
    #endif

    /// Without APRS and the map, the memories take the whole width.
    private var sideBySide: some View {
        HStack(spacing: 0) {
            if model.isAPRSEnabled || model.isMapEnabled {
                MemoriesView(model: model).frame(minWidth: 280, maxWidth: 400)
                Divider()
                SidePane(model: model).frame(minWidth: 320)
            } else {
                MemoriesView(model: model).frame(minWidth: 280)
            }
        }
    }
}

/// Beside the memories of a wide window: the packets, the chats or the map, of those that are on.
struct SidePane: View {
    @Bindable var model: RadioViewModel
    static let showsMapKey = "sideShowsMap"
    /// The map is shown rather than APRS, also after a restart.
    @AppStorage(showsMapKey) private var showsMap = false

    private enum Part: Hashable {
        case aprs(APRSPage), map
    }

    var body: some View {
        VStack(spacing: 0) {
            // Without APRS, the map has the side to itself.
            if model.isAPRSEnabled {
                Picker("Show", selection: part) {
                    Text("Packets").tag(Part.aprs(.packets))
                    Text(model.newAPRSMessages > 0 ? "Chats (\(model.newAPRSMessages))" : "Chats")
                        .tag(Part.aprs(.chats))
                    if model.isMapEnabled {
                        Text("Map").tag(Part.map)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal)
                .padding(.top, 6)
            }
            if isMapShown {
                MapPage(model: model)
            } else {
                APRSView(model: model)
            }
        }
        // A reply or a chat asked for elsewhere brings APRS back.
        .onChange(of: model.aprsReplyCount) { showsMap = false }
        .onChange(of: model.chatRequestCount) { showsMap = false }
        .onChange(of: model.packetsRequestCount) { showsMap = false }
        .onChange(of: model.aprsPage) { showsMap = false }
    }

    private var isMapShown: Bool {
        model.isMapEnabled && (showsMap || !model.isAPRSEnabled)
    }

    private var part: Binding<Part> {
        Binding(
            get: { isMapShown ? .map : .aprs(model.aprsPage) },
            set: { part in
                switch part {
                case .map: showsMap = true
                case .aprs(let page):
                    showsMap = false
                    model.aprsPage = page
                }
            }
        )
    }
}

#if os(iOS)
    /// The pages of the compact layout, in their order.
    enum CompactPage: String, CaseIterable, Identifiable {
        case memories, packets, chats, map, settings

        /// Where the page shown last is kept.
        static let storageKey = "mainPage"

        var id: Self { self }

        var title: String {
            switch self {
            case .memories: "Memories"
            case .packets: "Packets"
            case .chats: "Chats"
            case .map: "Map"
            case .settings: "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .memories: "list.bullet"
            case .packets: "point.3.connected.trianglepath.dotted"
            case .chats: "bubble.left.and.bubble.right"
            case .map: "map"
            case .settings: "gearshape"
            }
        }

        /// What the APRS page of a wider screen would show.
        var aprsPage: APRSPage? {
            switch self {
            case .packets: .packets
            case .chats: .chats
            case .memories, .map, .settings: nil
            }
        }
    }

    /// iPhone and narrow iPad windows: one page each for the memories, the APRS packets, the chats and the settings, in a
    /// ring, so that a swipe goes from the memories straight to the settings and back. The header and PTT stay outside
    /// the pages, so that a moving finger on PTT does not change the page and end the transmission.
    private struct CompactScreen: View {
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

        private typealias Page = CompactPage

        let model: RadioViewModel
        /// The page shown last, also after a restart.
        @AppStorage(CompactPage.storageKey) private var page = Page.memories
        /// Where the scroll view stands, which follows `page` and leads it when swiped.
        @State private var shownSlot: Slot?
        /// The bars below the pages make way for the keyboard, so that the line to write stays above it.
        @State private var isKeyboardShown = false
        /// The pages opened in the settings, below their list. While one is open, a swipe goes back to the list rather
        /// than to another page. `RootView` keeps them, for the wide layout to take them over.
        @Binding var settingsPath: [SettingsDestination]
        /// The sides of the screen that are not free, such as the strip below the status bar at the side of a foldable
        /// iPhone; the page bar stands there.
        @State private var sideInsets = EdgeInsets()
        /// The side where the system puts vertical bars, if it does: the page bar then stands there (ADR-0071).
        @Environment(\.verticalBarEdge) private var barEdge
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
                        if model.isMapEnabled {
                            pageView(.map) { MapPage(model: model) }
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
                // The scroll view draws into the sides of the screen that are not free, such as the status bar that a
                // foldable iPhone shows at the side, where the next page would show.
                .clipped()
                // On a page of the settings, a swipe goes back to their list.
                .scrollDisabled(page == .settings && !settingsPath.isEmpty)
                .scrollPosition(id: $shownSlot)
                .onAppear {
                    showMemoriesIfHidden()
                    shownSlot = .page(page)
                }
                .onChange(of: pages) {
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
                .onChange(of: model.packetsRequestCount) { withAnimation { page = .packets } }
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
                    if barEdge == nil {
                        pageBar(.horizontal)
                            .padding(.top, 4)
                            .background(Color.opaqueBar)
                    }
                }
            }
            .observesKeyboard($isKeyboardShown)
            .onGeometryChange(for: EdgeInsets.self, of: \.safeAreaInsets) { sideInsets = $0 }
            // The strip of the page bar at the side is a bar, and so is the edge below the pages.
            .background {
                if barEdge != nil { Color.opaqueBar.ignoresSafeArea() }
            }
            // Below the status bar at the side, where a system tab bar would stand; it takes no height from the pages.
            .overlay(alignment: barEdge == .leading ? .bottomLeading : .bottomTrailing) {
                if let barEdge {
                    pageBar(.vertical)
                        .frame(width: barEdge == .leading ? sideInsets.leading : sideInsets.trailing)
                        .ignoresSafeArea(.container, edges: barEdge == .leading ? .leading : .trailing)
                }
            }
        }

        /// The pages there are: without APRS, its two go, and the map without the map.
        private var pages: [Page] {
            Page.allCases.filter {
                switch $0 {
                case .packets, .chats: model.isAPRSEnabled
                case .map: model.isMapEnabled
                case .memories, .settings: true
                }
            }
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
        /// In a column at the side, the symbol stands near the edge of the screen, so the count stays closer to it.
        private func newMessages(_ axis: Axis) -> some View {
            CountBadge(count: model.newAPRSMessages, color: .red)
                .fixedSize()
                .offset(x: axis == .horizontal ? 10 : 2, y: -6)
        }

        /// A row below the pages, or a column at the side where the system puts vertical bars.
        private func pageBar(_ axis: Axis) -> some View {
            let layout = axis == .horizontal ? AnyLayout(HStackLayout()) : AnyLayout(VStackLayout(spacing: 12))
            return layout {
                ForEach(pages) { item in
                    Button {
                        withAnimation { page = item }
                    } label: {
                        Image(systemName: item.symbol)
                            .font(.title)
                            .imageScale(.large)
                            .overlay(alignment: .topTrailing) {
                                if item == .chats, model.newAPRSMessages > 0 {
                                    newMessages(axis)
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
        }
    }
#endif

extension EnvironmentValues {
    /// Whether the page that holds a view is the one shown, where pages sit side by side; elsewhere always.
    @Entry var isPageOnScreen = true
    /// The side where the system puts vertical bars, as a foldable iPhone does below its status bar; `nil` where it
    /// puts none, also before iOS 27.1. Set by `readsVerticalBarEdge()`.
    @Entry var verticalBarEdge: HorizontalEdge?
}

extension View {
    /// Passes on where the system puts vertical bars, which only iOS 27.1 and later tell.
    func readsVerticalBarEdge() -> some View {
        modifier(VerticalBarEdgeReader())
    }
}

private struct VerticalBarEdgeReader: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
            if #available(iOS 27.1, *) {
                content.modifier(Reader())
            } else {
                content
            }
        #else
            content
        #endif
    }

    #if os(iOS)
        @available(iOS 27.1, *)
        private struct Reader: ViewModifier {
            @Environment(\.toolbarVerticalEdge) private var edge

            func body(content: Content) -> some View {
                content.environment(\.verticalBarEdge, edge)
            }
        }
    #endif
}
