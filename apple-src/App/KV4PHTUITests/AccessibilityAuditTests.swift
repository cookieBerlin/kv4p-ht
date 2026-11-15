import XCTest

/// Apple's accessibility audit on every screen of the app, in its demo mode (ADR-0062). A finding fails the test unless
/// it is one of the exceptions the ADR names. Each one that fails is listed with a line that starts with `A11Y`, which
/// `make a11y` collects.
@MainActor
final class AccessibilityAuditTests: XCTestCase {
    private var app: XCUIApplication!
    private var findings: [String] = []

    override func setUp() async throws {
        connectToWindowServer()
        continueAfterFailure = true
        findings = []
    }

    func testDefaultTextSize() throws {
        try runAudit(textSize: nil)
    }

    func testLargestTextSize() throws {
        #if os(macOS)
            throw XCTSkip("The Mac has no Dynamic Type")
        #else
            try runAudit(textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        #endif
    }

    private func runAudit(textSize: String?) throws {
        app = XCUIApplication()
        // The small demo: with longer lists, the audit of a screen runs out of time on a slow machine.
        app.launchArguments = ["-uitest-demo", "-uitest-small-demo"]
        if let textSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
        }
        app.launch()
        let size = textSize == nil ? "default" : "largest"
        XCTAssertTrue(app.waitForStart(), "The app did not start")
        #if os(macOS)
            app.closeAbout()
        #endif
        try audit("\(size) memories")
        app.showPage("Packets")
        try audit("\(size) packets")
        if app.openPanel("packet-filter") {
            try audit("\(size) packet filter")
            _ = app.closePanel("packet-filter")
        } else {
            let finding = "A11Y \(size) packet filter: did not open"
            print(finding)
            findings.append(finding)
        }
        app.showPage("Chats")
        try audit("\(size) chats")
        let chat = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'N1CALL'")).firstMatch
        if chat.waitForExistence(timeout: 2) {
            chat.press()
            try audit("\(size) chat")
            let back = app.buttons["chat-back"].firstMatch
            if back.waitForExistence(timeout: 2) {
                back.press()
            } else {
                let finding = "A11Y \(size) chat: did not open"
                print(finding)
                findings.append(finding)
            }
        }
        app.showPage("Map")
        // The tiles come from the network; they are Apple's, so the audit waits for the controls only.
        Thread.sleep(forTimeInterval: 2)
        try audit("\(size) map")
        if app.openPanel("map-layers") {
            try audit("\(size) map layers")
            _ = app.closePanel("map-layers")
        } else {
            let finding = "A11Y \(size) map layers: did not open"
            print(finding)
            findings.append(finding)
        }
        let list = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'List'"))
            .allElementsBoundByIndex.first(where: \.isHittable)
        list?.tapOrClick()
        try audit("\(size) map list")
        app.showPage("Settings")
        try audit("\(size) settings")
        // In the list of the settings, as "Memories" and "APRS" also name pages of the bar below.
        for page in ["Station", "Pages", "Radio", "Transmit", "Audio", "APRS", "Memories", "Simulator", "Logging"] {
            try auditSettings(page, size: size)
        }
        #if os(macOS)
            try auditAbout()
        #else
            try auditWhatsNew(size: size)
        #endif
        let report = findings.isEmpty ? "A11Y \(size): no findings" : findings.joined(separator: "\n")
        XCTAssertTrue(findings.isEmpty, "\(findings.count) findings with \(size) text")
        let attachment = XCTAttachment(string: report)
        attachment.name = "Accessibility findings, \(size) text"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    #if os(macOS)
        /// A page of the settings window, chosen in its sidebar.
        private func auditSettings(_ page: String, size: String) throws {
            let row = app.descendants(matching: .any)["settings-\(page)"].firstMatch
            guard row.waitForExistence(timeout: 2) else {
                // A page without anything to set has no row, such as the simulator's without the simulator; the first
                // page always has one, or the sidebar cannot be found.
                guard page != "Station" else {
                    let finding = "A11Y \(size) settings: no sidebar"
                    print(finding)
                    findings.append(finding)
                    return
                }
                print("A11Y-NOT-OFFERED \(size) settings \(page)")
                return
            }
            row.click()
            Thread.sleep(forTimeInterval: 1)
            try audit("\(size) settings \(page)")
        }

        /// The About window, which the app menu opens: the first menu after Apple's.
        private func auditAbout() throws {
            app.activate()
            app.menuBars.menuBarItems.element(boundBy: 1).click()
            app.menuItems["About kv4p HT"].firstMatch.click()
            XCTAssertTrue(app.windows["About kv4p HT"].waitForExistence(timeout: 5), "The About window did not open")
            try audit("default about")
            try auditWhatsNew(size: "default")
            app.closeAbout()
        }
    #else
        /// A page of the settings, opened from their list and closed again.
        private func auditSettings(_ page: String, size: String) throws {
            let link = app.buttons["settings-\(page)"].firstMatch
            switch reveal(link) {
            case .onScreen: break
            case .notOffered: return
            case .notReached:
                let finding = "A11Y \(size) settings \(page): not reached"
                print(finding)
                findings.append(finding)
                return
            }
            link.tap()
            try audit("\(size) settings \(page)")
            let back = app.navigationBars.buttons["Settings"].firstMatch
            if back.waitForExistence(timeout: 2) { back.tap() }
        }
    #endif

    /// What's new, opened from About: the whole changelog (ADR-0069). On iPhone and iPad, About is the last link of the
    /// settings.
    private func auditWhatsNew(size: String) throws {
        #if os(iOS)
            let about = app.buttons["About kv4p HT"].firstMatch
            guard reveal(about) == .onScreen else {
                let finding = "A11Y \(size) about: not reached"
                print(finding)
                findings.append(finding)
                return
            }
            about.tap()
        #endif
        let whatsNew = app.buttons["about-whats-new"].firstMatch
        #if os(iOS)
            // With the largest text, About's form makes the row only once it comes near.
            _ = whatsNew.waitForExistence(timeout: 5) || reveal(whatsNew) == .onScreen
        #endif
        guard whatsNew.waitForExistence(timeout: 5) else {
            let finding = "A11Y \(size) whats new: not reached"
            print(finding)
            findings.append(finding)
            return
        }
        whatsNew.press()
        let done = app.buttons["whats-new-done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5), "What's new did not open")
        try audit("\(size) whats new")
        done.press()
        #if os(iOS)
            let back = app.navigationBars.buttons["Settings"].firstMatch
            if back.waitForExistence(timeout: 2) { back.tap() }
        #endif
    }

    #if os(iOS)
        /// Scrolls the settings until the link is on screen: the list makes rows out of sight only once they come near,
        /// and after a page, the list may stand below or above the next link. The swipe starts in the middle of the screen,
        /// as the pages beside it hold lists too.
        private func reveal(_ link: XCUIElement) -> Reveal {
            var wasSeen = false
            for isDown in [false, true] {
                for _ in 0..<8 {
                    wasSeen = wasSeen || link.exists
                    if link.exists, link.isHittable { return .onScreen }
                    if isDown { app.swipeDown() } else { app.swipeUp() }
                }
            }
            if link.exists, link.isHittable { return .onScreen }
            // A page without anything to set on this device, such as the audio on an iPad, has no link.
            return wasSeen || link.exists ? .notReached : .notOffered
        }

        private enum Reveal {
            case onScreen, notOffered, notReached
        }
    #endif

    /// Every kind of check on a screen. A screen with findings is checked once more after a pause, and only what both
    /// looks find counts: a slow machine lets the audit catch a screen before its text has grown, but seldom twice in the
    /// same place. A screen without findings says so, to show that it was checked.
    private func audit(_ screen: String) throws {
        // To judge a finding by looking at the screen; `make a11y` exports them.
        #if os(macOS)
            let screenshot = app.frontWindowScreenshot()
        #else
            let screenshot = XCTAttachment(screenshot: app.screenshot())
        #endif
        screenshot.name = screen
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let before = findings.count
        firstLook = []
        look = .first
        defer { look = .only }
        try auditEveryKind(screen)
        if findings.count > before {
            findings.removeSubrange(before...)
            look = .second
            Thread.sleep(forTimeInterval: Self.pauseBeforeLookingAgain)
            try auditEveryKind(screen)
        }
        if findings.count == before {
            print("A11Y \(screen): no findings")
        }
    }

    /// The look at a screen that a finding comes from. Those of the first look are printed as `A11Y-FIRST-LOOK`, and
    /// those that only the second look finds as `A11Y-ONCE`; `make a11y` counts neither.
    private enum Look {
        case only, first, second
    }

    private var look = Look.only
    /// What the first look at the screen found, each without the contrast measured on the screenshot.
    private var firstLook: Set<String> = []
    private static let pauseBeforeLookingAgain: TimeInterval = 3

    /// All kinds of check but Dynamic Type at once, which is quick; if that runs out of the time XCTest gives an audit on
    /// a busy simulator, one kind at a time, each with a few attempts. Dynamic Type runs on its own.
    private func auditEveryKind(_ screen: String) throws {
        let before = findings.count
        do {
            try runAudit(screen, Self.auditTypes)
        } catch let error as NSError where error.code == Self.timedOut {
            findings.removeSubrange(before...)
            for type in Self.eachAuditType {
                try runAuditRetrying(screen, type)
            }
        }
        #if os(iOS)
            // On its own: together with the other kinds, it flags text that grows, such as all of a chat.
            try runAuditRetrying(screen, .dynamicType)
        #endif
    }

    /// The kinds of check of each platform, but Dynamic Type, which runs on its own.
    #if os(macOS)
        private static let eachAuditType: [XCUIAccessibilityAuditType] = [
            .contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .action, .parentChild,
        ]
    #else
        private static let eachAuditType: [XCUIAccessibilityAuditType] = [
            .contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .textClipped, .trait,
        ]
    #endif
    private static let auditTypes = XCUIAccessibilityAuditType(eachAuditType)
    /// The error of an audit that ran out of time.
    private static let timedOut = -56

    /// A busy simulator lets an audit of one kind run out of time now and then; after a pause, which grows with each
    /// attempt, it runs again, and the last time it counts.
    private func runAuditRetrying(_ screen: String, _ type: XCUIAccessibilityAuditType) throws {
        for attempt in 1..<Self.attempts {
            do {
                return try runAudit(screen, type)
            } catch let error as NSError where error.code == Self.timedOut {
                print("A11Y-TIMED-OUT \(screen): \(Self.name(of: type)), attempt \(attempt)")
                Thread.sleep(forTimeInterval: TimeInterval(2 * attempt))
            }
        }
        try runAudit(screen, type)
    }

    private static let attempts = 5

    private func runAudit(_ screen: String, _ type: XCUIAccessibilityAuditType) throws {
        pass = Pass(app: app)
        try app.performAccessibilityAudit(for: type) { issue in
            // An element that went since, such as a part of the map that MapKit draws anew, cannot be read any more;
            // the second look finds it again if it stays (ADR-0062).
            let seen = issue.element.flatMap(Seen.init)
            if issue.element != nil, seen == nil {
                print("A11Y-GONE \(screen): \(Self.name(of: issue.auditType))")
                return true
            }
            if let exception = self.exception(for: issue, seen, on: screen) {
                print("A11Y-EXCEPTION \(exception): \(screen): \(Self.describe(issue, seen))")
                return true
            }
            let place = "\(screen): \(Self.describe(issue, seen))"
            var finding = "A11Y \(place)"
            if issue.auditType == .contrast, let seen {
                let measured = self.measuredContrast(in: seen.frame).map { String(format: "%.1f:1", $0) } ?? "none"
                finding += " — measured \(measured) in \(seen.frame)"
            }
            switch self.look {
            case .first:
                print("A11Y-FIRST-LOOK" + finding.dropFirst("A11Y".count))
                self.firstLook.insert(place)
            case .second where !self.firstLook.contains(place):
                print("A11Y-ONCE" + finding.dropFirst("A11Y".count))
                return true
            case .only, .second:
                // At once, so that a run that stops early keeps what it found.
                print(finding)
            }
            self.findings.append(finding)
            // Handled here, as the test fails on its findings at the end: an issue of XCTest would attach a screenshot of
            // the whole screen, which on the Mac shows whatever else is open.
            return true
        }
    }

    private static func describe(_ issue: XCUIAccessibilityAuditIssue, _ seen: Seen?) -> String {
        // Without an element, the long description tells where it is.
        // The Mac names many elements by nothing but their place.
        let element =
            seen.map { seen in
                let identifier = seen.identifier.isEmpty ? "" : " #\(seen.identifier)"
                return "\(name(of: seen.elementType)) '\(seen.label)'\(identifier) at \(seen.frame)"
            }
            ?? "no element: \(issue.detailedDescription)"
        return "\(name(of: issue.auditType)) — \(issue.compactDescription) — \(element)"
    }

    /// An element of a finding. Each question to an element is a query of its own, of a tenth of a second, and the
    /// exceptions ask the same ones again and again; so each is asked once, when first needed. Not by a snapshot, which
    /// also reads all the element holds, such as all of a window for a group as large as it.
    @MainActor
    private final class Seen {
        let element: XCUIElement

        /// None for an element that went since.
        init?(_ element: XCUIElement) {
            guard element.exists else { return nil }
            self.element = element
        }

        lazy var elementType = element.elementType
        lazy var label = element.label
        lazy var identifier = element.identifier
        lazy var frame = element.frame
    }

    /// What the exceptions ask of the app around a finding, the same for all findings of one audit: each asked once, when
    /// first needed.
    @MainActor
    private final class Pass {
        private let app: XCUIApplication

        init(app: XCUIApplication) {
            self.app = app
        }

        /// The frames of the lists, which a row may stick out of.
        lazy var listFrames: [CGRect] =
            (app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex)
            .map(\.frame)

        /// The screen as it is now, and the frame it shows: the app's window, which an iPad may place elsewhere, or on
        /// the Mac the whole main screen.
        lazy var screenshot: (image: CGImage, frame: CGRect)? = {
            #if os(macOS)
                // The main screen spans its menu bar, and the frames start at its top left corner.
                let image = XCUIScreen.main.screenshot().image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                let frame = app.menuBars.firstMatch.frame
            #else
                let image = app.screenshot().image.cgImage
                let frame = app.frame
            #endif
            guard let image, frame.width > 0 else { return nil }
            return (image, frame)
        }()

        #if os(macOS)
            lazy var frontWindowFrame = app.windows.firstMatch.frame
            lazy var windowFrames = app.windows.allElementsBoundByIndex.map(\.frame)
            lazy var sheetFrame = frame(of: app.sheets.firstMatch)
            lazy var popoverFrame = frame(of: app.popovers.firstMatch)
            lazy var mapFrame = frame(of: app.descendants(matching: .any)["map"].firstMatch)
            lazy var mapListFrame = frame(of: app.descendants(matching: .any)["map-list"].firstMatch)
            lazy var touchBarFrame = frame(of: app.touchBars.firstMatch)

            private func frame(of element: XCUIElement) -> CGRect? {
                element.exists ? element.frame : nil
            }
        #endif
    }

    private var pass: Pass!

    // MARK: Exceptions (ADR-0062)

    /// The number of the exception in ADR-0062 that covers a finding, if one does.
    /// The map, also with its layers open over it.
    private func isMap(_ screen: String) -> Bool {
        screen.hasSuffix(" map") || screen.hasSuffix(" map layers")
    }

    /// A panel of choices, a form in a sheet or a popover (ADR-0068).
    private func isPanel(_ screen: String) -> Bool {
        screen.hasSuffix(" packet filter") || screen.hasSuffix(" map layers")
    }

    private func exception(for issue: XCUIAccessibilityAuditIssue, _ seen: Seen?, on screen: String) -> Int? {
        let label = seen?.label ?? ""
        let elementType = seen?.elementType
        let isContrast = issue.auditType == .contrast
        #if os(macOS)
            let isDynamicType = false
            let isTrait = false
            let isTextClipped = false
        #else
            let isDynamicType = issue.auditType == .dynamicType
            let isTrait = issue.auditType == .trait
            let isTextClipped = issue.auditType == .textClipped
        #endif
        // 1. Withdrawn: contrast that nearly passes is measured as any other, by 2.
        #if os(macOS)
            // 11 before 2, as it needs no screenshot: text in a window behind the front one, which macOS dims, or cut off
            // at the front one's edge; also text of a window behind a sheet open on it, such as About behind What's New.
            if isContrast, let seen, isBehindTheFront(seen.frame) { return 11 }
        #endif
        // 2. Enough contrast on the screenshot: the audit misreads the background now and then, such as the material of a
        // bar. Or none to read: a row that a list scrolls below a bar is covered, and cannot be tapped either.
        if isContrast, let seen {
            if isCutOff(seen.frame) || !seen.element.isHittable {
                print("A11Y-COVERED \(screen): \(label)")
                return 2
            }
            if let contrast = measuredContrast(in: seen.frame), contrast >= Self.minimumContrast {
                print("A11Y-MEASURED \(String(format: "%.1f", contrast)):1 \(screen): \(label)")
                return 2
            }
        }
        // 3. Sizes kept on purpose: the header, the page bar with its count, and PTT; and the titles of a sliding switch,
        // which give way to its symbols at larger sizes.
        if isDynamicType, Self.isCappedOnPurpose(label) || seen?.identifier == "switch-title" { return 3 }
        // 4. SwiftUI's text fields, whose text grows on the screenshots.
        if isDynamicType, elementType == .textField { return 4 }
        // 5. SwiftUI's disabled choices, which VoiceOver reads as dimmed all the same.
        if isTrait, issue.compactDescription.contains("NotEnabled") { return 5 }
        // 6. The rows of SwiftUI's lists and forms, which wrap on the screenshots rather than being cut: the settings and
        // the panels of choices.
        if isDynamicType || isTextClipped, screen.contains("settings") || isPanel(screen) || label == "New chat" {
            return 6
        }
        // 6. The long entries of the changelog, which wrap on the screenshots rather than being cut.
        if isTextClipped, screen.hasSuffix("whats new") { return 6 }
        // 7. Findings without an element, which no screen element can be matched to.
        guard let seen else { return 7 }
        // 13. The legal notice MapKit puts on the map, with its own small link (ADR-0068).
        if issue.auditType == .hitRegion, label == "Legal", isMap(screen) { return 13 }
        // 14. The mark of the band in a marker of the map, which MapKit draws in a size of its own.
        if isDynamicType || isTextClipped, ["2m", "70", "•"].contains(label), isMap(screen) { return 14 }
        #if os(macOS)
            return macException(for: issue, seen, on: screen)
        #else
            return nil
        #endif
    }

    #if os(macOS)
        /// The exceptions of the Mac, where SwiftUI and AppKit add parts of their own.
        private func macException(for issue: XCUIAccessibilityAuditIssue, _ seen: Seen, on screen: String) -> Int? {
            let isUnnamedGroup = seen.elementType == .group && seen.label.isEmpty
            let isDescription = issue.auditType == .sufficientElementDescription
            // 8. SwiftUI's pop-up buttons, which VoiceOver opens by showing their menu rather than by pressing them.
            if issue.auditType == .action, seen.elementType == .popUpButton { return 8 }
            // 9. The groups that SwiftUI puts around the content of a window and its columns, as high as the window, and
            // around the content of a sheet or a popover, as large as it; and the popover itself, which takes no name.
            if isDescription, isUnnamedGroup, isAsHighAsAWindow(seen.frame) || isTheSheet(seen.frame) { return 9 }
            if isDescription, seen.label.isEmpty, seen.elementType == .popover || seen.elementType == .group,
                isThePopover(seen.frame)
            {
                return 9
            }
            // 10. The knob of a slider, a part of AppKit's own; the slider has the name.
            if isDescription, seen.elementType == .valueIndicator { return 10 }
            // 15. The markers MapKit draws on the Mac, without names; VoiceOver has the list of the map instead.
            if isMap(screen), pass.mapFrame?.contains(seen.frame) == true { return 15 }
            // 16. The Touch Bar that AppKit makes for a text field with the focus, such as the frequency, and its items.
            if isDescription, isInTouchBar(seen) { return 16 }
            // 12. The header of a section of a SwiftUI list: the groups of memories, and the memories and stations of the
            // map, whose list stays in the main window behind the other screens.
            if isDescription || issue.auditType == .parentChild, isUnnamedGroup,
                screen.hasSuffix("settings Memories") || pass.mapListFrame?.contains(seen.frame) == true
            {
                return 12
            }
            return nil
        }

        /// Outside the front window, or outside the sheet open on it, which macOS dims with the rest of its window.
        private func isBehindTheFront(_ frame: CGRect) -> Bool {
            if !pass.frontWindowFrame.contains(frame) { return true }
            return pass.sheetFrame.map { !$0.contains(frame) } ?? false
        }

        /// The Touch Bar itself, or one of its items, which may stick out of it by a point.
        private func isInTouchBar(_ seen: Seen) -> Bool {
            seen.elementType == .touchBar
                || pass.touchBarFrame?.insetBy(dx: -2, dy: -2).contains(seen.frame) == true
        }

        private func isThePopover(_ frame: CGRect) -> Bool {
            guard let popover = pass.popoverFrame else { return false }
            return popover.contains(frame) && popover.width == frame.width
        }

        private func isTheSheet(_ frame: CGRect) -> Bool {
            guard let sheet = pass.sheetFrame else { return false }
            return sheet.contains(frame) && sheet.width == frame.width
        }

        private func isAsHighAsAWindow(_ frame: CGRect) -> Bool {
            pass.windowFrames.contains { window in
                window.minY == frame.minY && window.height == frame.height
            }
        }
    #endif

    /// A row that sticks out of its list, below a bar: still hittable by the part that shows.
    private func isCutOff(_ frame: CGRect) -> Bool {
        pass.listFrames.contains { list in
            list.intersects(frame) && !list.contains(frame)
        }
    }

    /// WCAG's minimum for text, which the audit's contrast check stands for.
    private static let minimumContrast = 4.5

    /// The contrast of an element on a screenshot: its lightest against its darkest pixel, which for text is the text
    /// against its background. Its frame may hold more than that, so this is the best case of the element.
    private func measuredContrast(in frame: CGRect) -> Double? {
        // Taken once for each audit, as a list may have moved since the screen was opened.
        guard let (image, window) = pass.screenshot else { return nil }
        let scale = CGFloat(image.width) / window.width
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect = frame.offsetBy(dx: -window.minX, dy: -window.minY)
            .applying(CGAffineTransform(scaleX: scale, y: scale)).integral.intersection(bounds)
        guard !rect.isEmpty, let crop = image.cropping(to: rect),
            let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        let width = crop.width
        let height = crop.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let isDrawn = pixels.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard isDrawn else { return nil }
        var darkest = 1.0
        var lightest = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let value = Self.luminance(pixels[index], pixels[index + 1], pixels[index + 2])
            darkest = min(darkest, value)
            lightest = max(lightest, value)
        }
        return (lightest + 0.05) / (darkest + 0.05)
    }

    /// The relative luminance of an sRGB colour (WCAG).
    private static func luminance(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Double {
        func linear(_ component: UInt8) -> Double {
            let value = Double(component) / 255
            return value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The header's texts and buttons, the page bar's count and PTT.
    private static func isCappedOnPurpose(_ label: String) -> Bool {
        let header = ["MHz", "VHF", "UHF", "Connect", "Disconnect", "Simulator", "Push to talk"]
        return header.contains(label) || label.wholeMatch(of: /S\d.*|\d+/) != nil
    }

    private static func name(of type: XCUIAccessibilityAuditType) -> String {
        switch type {
        case .contrast: "contrast"
        case .elementDetection: "element detection"
        case .hitRegion: "hit region"
        case .sufficientElementDescription: "description"
        #if os(macOS)
            case .action: "action"
            case .parentChild: "parent and child"
        #else
            case .dynamicType: "Dynamic Type"
            case .textClipped: "text clipped"
            case .trait: "trait"
        #endif
        default: "type \(type.rawValue)"
        }
    }

    private static func name(of type: XCUIElement.ElementType) -> String {
        switch type {
        case .button: "button"
        case .staticText: "text"
        case .textField: "text field"
        case .image: "image"
        case .switch: "switch"
        case .slider: "slider"
        case .cell: "cell"
        case .group: "group"
        case .popUpButton: "pop-up button"
        case .menuButton: "menu button"
        case .radioButton: "radio button"
        case .outline: "outline"
        case .valueIndicator: "value indicator"
        case .other: "other"
        default: "element \(type.rawValue)"
        }
    }
}

extension XCUIElement {
    /// A tap, or a click on the Mac, where a tap does not press a button.
    fileprivate func press() {
        #if os(macOS)
            click()
        #else
            tap()
        #endif
    }
}
