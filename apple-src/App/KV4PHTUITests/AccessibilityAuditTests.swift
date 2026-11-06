import XCTest

/// Apple's accessibility audit on every screen of the app, in its demo mode (ADR-0062). Each finding is listed with a
/// line that starts with `A11Y`, which `make a11y` collects; until the findings are fixed, they do not fail the test.
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
        tapPage("APRS")
        try audit("\(size) packets")
        // With unread messages, the switch says how many, as "Chats (2)".
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Chats'")).firstMatch.tap()
        try audit("\(size) chats")
        let chat = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'N1CALL'")).firstMatch
        if chat.waitForExistence(timeout: 2) {
            chat.tap()
            try audit("\(size) chat")
            app.buttons["Chats"].firstMatch.tap()
        }
        app.buttons["Packets"].firstMatch.tap()
        tapPage("Settings")
        try audit("\(size) settings")
        // In the list of the settings, as "Memories" and "APRS" also name pages of the bar below.
        for page in ["Station", "Radio", "Transmit", "Audio", "APRS", "Memories", "Simulator", "Logging"] {
            let link = app.buttons["settings-\(page)"].firstMatch
            guard link.waitForExistence(timeout: 2) else { continue }
            // With the largest text, the lower pages are out of sight.
            for _ in 0..<6 where !link.isHittable {
                app.swipeUp()
            }
            guard link.isHittable else { continue }
            link.tap()
            try audit("\(size) settings \(page)")
            let back = app.navigationBars.buttons["Settings"].firstMatch
            if back.waitForExistence(timeout: 2) { back.tap() }
        }
        let report = findings.isEmpty ? "A11Y \(size): no findings" : findings.joined(separator: "\n")
        let attachment = XCTAttachment(string: report)
        attachment.name = "Accessibility findings, \(size) text"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The page bar of a phone; elsewhere the pages stand side by side, and the settings open from the toolbar.
    private func tapPage(_ title: String) {
        let pageButton = app.buttons["page-\(title)"].firstMatch
        if pageButton.exists {
            pageButton.tap()
            // The pages scroll into place; an audit before that sees two halves.
            let selected = NSPredicate(format: "isSelected == true")
            _ = XCTWaiter.wait(for: [expectation(for: selected, evaluatedWith: pageButton)], timeout: 5)
            Thread.sleep(forTimeInterval: 1)
        } else if title == "Settings" {
            app.buttons["Settings"].firstMatch.tap()
        }
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

    /// All kinds of check at once, which is quick; if that runs out of the time XCTest gives an audit on a busy
    /// simulator, one kind at a time, each once more if it does too. A screen without findings says so, to show that it
    /// was checked.
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
                do {
                    try runAudit(screen, type)
                } catch let error as NSError where error.code == Self.timedOut {
                    try runAudit(screen, type)
                }
            }
        }
        if findings.count == before {
            print("A11Y \(screen): no findings")
        }
    }

    private static let eachAuditType: [XCUIAccessibilityAuditType] = [
        .contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .dynamicType, .textClipped, .trait,
    ]
    private static let auditTypes = XCUIAccessibilityAuditType(eachAuditType)
    /// The error of an audit that ran out of time.
    private static let timedOut = -56

    private func runAudit(_ screen: String, _ type: XCUIAccessibilityAuditType) throws {
        try app.performAccessibilityAudit(for: type) { issue in
            let element = issue.element.map { "\(Self.name(of: $0.elementType)) '\($0.label)'" } ?? "no element"
            let finding = "A11Y \(screen): \(Self.name(of: issue.auditType)) — \(issue.compactDescription) — \(element)"
            // At once, so that a run that stops early keeps what it found.
            print(finding)
            self.findings.append(finding)
            return true
        }
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
