import XCTest

/// Apple's accessibility audit on every screen of the app, in its demo mode (ADR-0062). A finding fails the test unless
/// it is one of the exceptions the ADR names. Each one that fails is listed with a line that starts with `A11Y`, which
/// `make a11y` collects.
@MainActor
final class AccessibilityAuditTests: XCTestCase {
    private var app: XCUIApplication!
    private var findings: [String] = []

    override func setUp() async throws {
        continueAfterFailure = true
        findings = []
    }

    func testDefaultTextSize() throws {
        try runAudit(textSize: nil)
    }

    func testLargestTextSize() throws {
        try runAudit(textSize: "UICTContentSizeCategoryAccessibilityXXXL")
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
        try audit("\(size) memories")
        tapPage("Packets")
        try audit("\(size) packets")
        tapPage("Chats")
        try audit("\(size) chats")
        let chat = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'N1CALL'")).firstMatch
        if chat.waitForExistence(timeout: 2) {
            chat.tap()
            try audit("\(size) chat")
            app.buttons["chat-back"].firstMatch.tap()
        }
        tapPage("Settings")
        try audit("\(size) settings")
        // In the list of the settings, as "Memories" and "APRS" also name pages of the bar below.
        for page in ["Station", "Radio", "Transmit", "Audio", "APRS", "Memories", "Simulator", "Logging"] {
            let link = app.buttons["settings-\(page)"].firstMatch
            switch reveal(link) {
            case .onScreen: break
            case .notOffered: continue
            case .notReached:
                let finding = "A11Y \(size) settings \(page): not reached"
                print(finding)
                findings.append(finding)
                continue
            }
            link.tap()
            try audit("\(size) settings \(page)")
            let back = app.navigationBars.buttons["Settings"].firstMatch
            if back.waitForExistence(timeout: 2) { back.tap() }
        }
        let report = findings.isEmpty ? "A11Y \(size): no findings" : findings.joined(separator: "\n")
        XCTAssertTrue(findings.isEmpty, "\(findings.count) findings with \(size) text")
        let attachment = XCTAttachment(string: report)
        attachment.name = "Accessibility findings, \(size) text"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The page bar of a phone; elsewhere the memories and APRS stand side by side, APRS switches between the packets
    /// and the chats, and the settings open from the toolbar.
    private func tapPage(_ title: String) {
        let pageButton = app.buttons["page-\(title)"].firstMatch
        if !pageButton.exists, title == "Packets" || title == "Chats" {
            // With unread messages, the switch says how many, as "Chats (2)".
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch.tap()
        } else if pageButton.exists {
            pageButton.tap()
            // The pages scroll into place; an audit before that sees two halves.
            let selected = NSPredicate(format: "isSelected == true")
            _ = XCTWaiter.wait(for: [expectation(for: selected, evaluatedWith: pageButton)], timeout: 5)
            Thread.sleep(forTimeInterval: 1)
        } else if title == "Settings" {
            app.buttons["Settings"].firstMatch.tap()
        }
    }

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

    /// All kinds of check but Dynamic Type at once, which is quick; if that runs out of the time XCTest gives an audit on
    /// a busy simulator, one kind at a time, each up to three times. Dynamic Type runs on its own. A screen without
    /// findings says so, to show that it was checked.
    private func audit(_ screen: String) throws {
        // To judge a finding by looking at the screen; `make a11y` exports them.
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = screen
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let before = findings.count
        do {
            try runAudit(screen, Self.auditTypes)
        } catch let error as NSError where error.code == Self.timedOut {
            findings.removeSubrange(before...)
            for type in Self.eachAuditType {
                try runAuditRetrying(screen, type)
            }
        }
        // On its own: together with the other kinds, it flags text that grows, such as all of a chat.
        try runAuditRetrying(screen, .dynamicType)
        if findings.count == before {
            print("A11Y \(screen): no findings")
        }
    }

    private static let eachAuditType: [XCUIAccessibilityAuditType] = [
        .contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .textClipped, .trait,
    ]
    private static let auditTypes = XCUIAccessibilityAuditType(eachAuditType)
    /// The error of an audit that ran out of time.
    private static let timedOut = -56

    /// A busy simulator lets an audit of one kind run out of time now and then; the third time it counts.
    private func runAuditRetrying(_ screen: String, _ type: XCUIAccessibilityAuditType) throws {
        for _ in 1..<Self.attempts {
            do {
                return try runAudit(screen, type)
            } catch let error as NSError where error.code == Self.timedOut {
                continue
            }
        }
        try runAudit(screen, type)
    }

    private static let attempts = 3

    private func runAudit(_ screen: String, _ type: XCUIAccessibilityAuditType) throws {
        try app.performAccessibilityAudit(for: type) { issue in
            if let exception = self.exception(for: issue, on: screen) {
                print("A11Y-EXCEPTION \(exception): \(screen): \(Self.describe(issue))")
                return true
            }
            var finding = "A11Y \(screen): \(Self.describe(issue))"
            if issue.auditType == .contrast, let element = issue.element {
                let measured = self.measuredContrast(of: element).map { String(format: "%.1f:1", $0) } ?? "none"
                finding += " — measured \(measured) in \(element.frame)"
            }
            // At once, so that a run that stops early keeps what it found.
            print(finding)
            self.findings.append(finding)
            return false
        }
    }

    private static func describe(_ issue: XCUIAccessibilityAuditIssue) -> String {
        // Without an element, the long description tells where it is.
        let element =
            issue.element.map { "\(name(of: $0.elementType)) '\($0.label)'" }
            ?? "no element: \(issue.detailedDescription)"
        return "\(name(of: issue.auditType)) — \(issue.compactDescription) — \(element)"
    }

    // MARK: Exceptions (ADR-0062)

    /// The number of the exception in ADR-0062 that covers a finding, if one does.
    private func exception(for issue: XCUIAccessibilityAuditIssue, on screen: String) -> Int? {
        let label = issue.element?.label ?? ""
        let elementType = issue.element?.elementType
        let isContrast = issue.auditType == .contrast
        let isDynamicType = issue.auditType == .dynamicType
        // 1. Apple's secondary grey, a little below the line, also in the footers of the settings.
        if isContrast, issue.compactDescription.contains("nearly passed") { return 1 }
        if isContrast, screen.contains("settings"), elementType == .staticText { return 1 }
        // 2. Enough contrast on the screenshot: the audit misreads the background now and then, such as the material of a
        // bar. Or none to read: a row that a list scrolls below a bar is covered, and cannot be tapped either.
        if isContrast, let element = issue.element {
            if !element.isHittable {
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
        if issue.auditType == .trait, issue.compactDescription.contains("NotEnabled") { return 5 }
        // 6. The rows of SwiftUI's lists and forms, which wrap on the screenshots rather than being cut.
        if isDynamicType || issue.auditType == .textClipped, screen.contains("settings") || label == "New chat" {
            return 6
        }
        // 7. Findings without an element, which no screen element can be matched to.
        if issue.element == nil { return 7 }
        // 8. The status above PTT, which grows on the screenshots; two audits of the same screen flag it once and once not.
        if isDynamicType, label == "Connected" { return 8 }
        return nil
    }

    /// WCAG's minimum for text, which the audit's contrast check stands for.
    private static let minimumContrast = 4.5

    /// The contrast of an element on a screenshot: its lightest against its darkest pixel, which for text is the text
    /// against its background. Its frame may hold more than that, so this is the best case of the element.
    private func measuredContrast(of element: XCUIElement) -> Double? {
        // Taken now, as a list may have moved since the screen was opened.
        guard let image = app.screenshot().image.cgImage, app.frame.width > 0 else { return nil }
        let scale = CGFloat(image.width) / app.frame.width
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        // The frame is on the screen, the screenshot shows the app's window, which an iPad may place elsewhere.
        let window = app.frame
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
        case .dynamicType: "Dynamic Type"
        case .textClipped: "text clipped"
        case .trait: "trait"
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
        case .other: "other"
        default: "element \(type.rawValue)"
        }
    }
}
