import XCTest

#if os(macOS)
    import ImageIO
    import UniformTypeIdentifiers
#endif

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
        app.launchArguments = ["-uitest-demo"]
        if let textSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
        }
        app.launch()
        let size = textSize == nil ? "default" : "largest"
        XCTAssertTrue(waitForStart(), "The app did not start")
        #if os(macOS)
            app.closeAbout()
        #endif
        try audit("\(size) memories")
        tapPage("Packets")
        try audit("\(size) packets")
        tapPage("Chats")
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
        tapPage("Map")
        // The tiles come from the network; they are Apple's, so the audit waits for the controls only.
        Thread.sleep(forTimeInterval: 2)
        try audit("\(size) map")
        let list = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'List'"))
            .allElementsBoundByIndex.first(where: \.isHittable)
        list?.tapOrClick()
        try audit("\(size) map list")
        tapPage("Settings")
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

    /// The page bar of a phone; elsewhere the memories stand beside a switch between the packets, the chats and the
    /// map, and the settings open from the toolbar.
    private func tapPage(_ title: String) {
        let pageButton = app.buttons["page-\(title)"].firstMatch
        if !pageButton.exists, ["Packets", "Chats", "Map"].contains(title) {
            // With unread messages, the switch says how many, as "Chats (2)". The Mac shows its parts as radio buttons.
            let part = NSPredicate(format: "label BEGINSWITH %@", title)
            #if os(macOS)
                app.radioButtons.matching(part).firstMatch.click()
            #else
                app.buttons.matching(part).firstMatch.tap()
            #endif
        } else if pageButton.exists {
            pageButton.tap()
            // The pages scroll into place; an audit before that sees two halves.
            let selected = NSPredicate(format: "isSelected == true")
            _ = XCTWaiter.wait(for: [expectation(for: selected, evaluatedWith: pageButton)], timeout: 5)
            Thread.sleep(forTimeInterval: 1)
        } else if title == "Settings" {
            #if os(macOS)
                app.typeKey(",", modifierFlags: .command)
            #else
                app.buttons["Settings"].firstMatch.tap()
            #endif
        }
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

    /// The page bar on a phone, or PTT elsewhere, whatever the text size.
    private func waitForStart() -> Bool {
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if app.buttons["page-Memories"].exists || app.buttons["Push to talk"].exists {
                return true
            }
            Thread.sleep(forTimeInterval: 1)
        }
        return false
    }

    /// Every kind of check on a screen. A screen with findings is checked once more after a pause, and only what both
    /// looks find counts: a slow machine lets the audit catch a screen before its text has grown, but seldom twice in the
    /// same place. A screen without findings says so, to show that it was checked.
    private func audit(_ screen: String) throws {
        // To judge a finding by looking at the screen; `make a11y` exports them.
        #if os(macOS)
            let screenshot = windowScreenshot()
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

    #if os(macOS)
        /// The front window, cut out of the screen, which shows whatever else is open. The test runner cannot take a
        /// window on its own.
        private func windowScreenshot() -> XCTAttachment {
            let data = NSMutableData()
            let frame = app.windows.firstMatch.frame
            if let image = XCUIScreen.main.screenshot().image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                let scale = screenScale(of: image),
                let window = image.cropping(to: frame.applying(CGAffineTransform(scaleX: scale, y: scale)).integral),
                let png = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
            {
                CGImageDestinationAddImage(png, window, nil)
                CGImageDestinationFinalize(png)
            }
            return XCTAttachment(data: data as Data, uniformTypeIdentifier: UTType.png.identifier)
        }

        /// The pixels of the main screen for each point: its menu bar spans it, and the test runner cannot ask AppKit.
        private func screenScale(of image: CGImage) -> CGFloat? {
            let width = app.menuBars.firstMatch.frame.width
            return width > 0 ? CGFloat(image.width) / width : nil
        }
    #endif

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
        try app.performAccessibilityAudit(for: type) { issue in
            // An element that went since, such as a part of the map that MapKit draws anew, cannot be read any more;
            // the second look finds it again if it stays (ADR-0062).
            if let element = issue.element, !element.exists {
                print("A11Y-GONE \(screen): \(Self.name(of: issue.auditType))")
                return true
            }
            if let exception = self.exception(for: issue, on: screen) {
                print("A11Y-EXCEPTION \(exception): \(screen): \(Self.describe(issue))")
                return true
            }
            let place = "\(screen): \(Self.describe(issue))"
            var finding = "A11Y \(place)"
            if issue.auditType == .contrast, let element = issue.element {
                let measured = self.measuredContrast(of: element).map { String(format: "%.1f:1", $0) } ?? "none"
                finding += " — measured \(measured) in \(element.frame)"
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

    private static func describe(_ issue: XCUIAccessibilityAuditIssue) -> String {
        // Without an element, the long description tells where it is.
        // The Mac names many elements by nothing but their place.
        let element =
            issue.element.map { element in
                let identifier = element.identifier.isEmpty ? "" : " #\(element.identifier)"
                return "\(name(of: element.elementType)) '\(element.label)'\(identifier) at \(element.frame)"
            }
            ?? "no element: \(issue.detailedDescription)"
        return "\(name(of: issue.auditType)) — \(issue.compactDescription) — \(element)"
    }

    // MARK: Exceptions (ADR-0062)

    /// The number of the exception in ADR-0062 that covers a finding, if one does.
    private func exception(for issue: XCUIAccessibilityAuditIssue, on screen: String) -> Int? {
        let label = issue.element?.label ?? ""
        let elementType = issue.element?.elementType
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
        // 1. Apple's secondary grey, a little below the line, also in the footers of the settings.
        if isContrast, issue.compactDescription.contains("nearly passed") { return 1 }
        if isContrast, screen.contains("settings"), elementType == .staticText { return 1 }
        // 2. Enough contrast on the screenshot: the audit misreads the background now and then, such as the material of a
        // bar. Or none to read: a row that a list scrolls below a bar is covered, and cannot be tapped either.
        if isContrast, let element = issue.element {
            if !element.isHittable || isCutOff(element) {
                print("A11Y-COVERED \(screen): \(label)")
                return 2
            }
            if let contrast = measuredContrast(of: element), contrast >= Self.minimumContrast {
                print("A11Y-MEASURED \(String(format: "%.1f", contrast)):1 \(screen): \(label)")
                return 2
            }
        }
        // 3. Sizes kept on purpose: the header, the page bar with its count, and PTT.
        if isDynamicType, Self.isCappedOnPurpose(label) { return 3 }
        // 4. SwiftUI's text fields, whose text grows on the screenshots.
        if isDynamicType, elementType == .textField { return 4 }
        // 5. SwiftUI's disabled choices, which VoiceOver reads as dimmed all the same.
        if isTrait, issue.compactDescription.contains("NotEnabled") { return 5 }
        // 6. The rows of SwiftUI's lists and forms, which wrap on the screenshots rather than being cut.
        if isDynamicType || isTextClipped, screen.contains("settings") || label == "New chat" {
            return 6
        }
        // 6. The long entries of the changelog, which wrap on the screenshots rather than being cut.
        if isTextClipped, screen.hasSuffix("whats new") { return 6 }
        // 7. Findings without an element, which no screen element can be matched to.
        if issue.element == nil { return 7 }
        // 13. The legal notice MapKit puts on the map, with its own small link (ADR-0068).
        if issue.auditType == .hitRegion, label == "Legal", screen.hasSuffix(" map") { return 13 }
        // 14. The mark of the band in a marker of the map, which MapKit draws in a size of its own.
        if isDynamicType || isTextClipped, ["2m", "70", "•"].contains(label), screen.hasSuffix(" map") { return 14 }
        #if os(macOS)
            if let element = issue.element, let exception = macException(for: issue, element, on: screen) {
                return exception
            }
        #endif
        return nil
    }

    #if os(macOS)
        /// The exceptions of the Mac, where SwiftUI and AppKit add parts of their own.
        private func macException(for issue: XCUIAccessibilityAuditIssue, _ element: XCUIElement, on screen: String)
            -> Int?
        {
            let isUnnamedGroup = element.elementType == .group && element.label.isEmpty
            let isDescription = issue.auditType == .sufficientElementDescription
            // 8. SwiftUI's pop-up buttons, which VoiceOver opens by showing their menu rather than by pressing them.
            if issue.auditType == .action, element.elementType == .popUpButton { return 8 }
            // 9. The groups that SwiftUI puts around the content of a window and its columns, as high as the window.
            if isDescription, isUnnamedGroup, isAsHighAsAWindow(element) { return 9 }
            // 10. The knob of a slider, a part of AppKit's own; the slider has the name.
            if isDescription, element.elementType == .valueIndicator { return 10 }
            // 11. Text in a window behind the front one, which macOS dims, or cut off at the front one's edge.
            if issue.auditType == .contrast, !app.windows.firstMatch.frame.contains(element.frame) { return 11 }
            // 15. The markers MapKit draws on the Mac, without names; VoiceOver has the list of the map instead.
            if screen.hasSuffix(" map"), isInMap(element) { return 15 }
            // 12. The header of a section of a SwiftUI list: the groups of memories, and the memories and stations of the
            // map, whose list stays in the main window behind the other screens.
            if isDescription || issue.auditType == .parentChild, isUnnamedGroup,
                screen.hasSuffix("settings Memories") || isInMapList(element)
            {
                return 12
            }
            return nil
        }

        private func isInMapList(_ element: XCUIElement) -> Bool {
            let list = app.descendants(matching: .any)["map-list"].firstMatch
            return list.exists && list.frame.contains(element.frame)
        }

        /// The map itself, or a part MapKit draws on it.
        private func isInMap(_ element: XCUIElement) -> Bool {
            let map = app.descendants(matching: .any)["map"].firstMatch
            return map.exists && map.frame.contains(element.frame)
        }

        private func isAsHighAsAWindow(_ element: XCUIElement) -> Bool {
            app.windows.allElementsBoundByIndex.contains { window in
                window.frame.minY == element.frame.minY && window.frame.height == element.frame.height
            }
        }
    #endif

    /// A row that sticks out of its list, below a bar: still hittable by the part that shows.
    private func isCutOff(_ element: XCUIElement) -> Bool {
        let lists = app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex
        return lists.contains { list in
            list.frame.intersects(element.frame) && !list.frame.contains(element.frame)
        }
    }

    /// WCAG's minimum for text, which the audit's contrast check stands for.
    private static let minimumContrast = 4.5

    /// The contrast of an element on a screenshot: its lightest against its darkest pixel, which for text is the text
    /// against its background. Its frame may hold more than that, so this is the best case of the element.
    private func measuredContrast(of element: XCUIElement) -> Double? {
        // Taken now, as a list may have moved since the screen was opened. The frame is on the screen; the screenshot
        // shows the app's window, which an iPad may place elsewhere, or on the Mac the whole main screen.
        #if os(macOS)
            // The main screen spans its menu bar, and the frames start at its top left corner.
            let image = XCUIScreen.main.screenshot().image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            let window = app.menuBars.firstMatch.frame
        #else
            let image = app.screenshot().image.cgImage
            let window = app.frame
        #endif
        guard let image, window.width > 0 else { return nil }
        let scale = CGFloat(image.width) / window.width
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect = element.frame.offsetBy(dx: -window.minX, dy: -window.minY)
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
