import XCTest

// iPhone and iPad only: the Mac's UI tests take over the mouse, and the line looks the same there.
#if os(iOS)
    /// The line to write an APRS message below the packets: the recipient field says itself what empty means, and Send
    /// is a button to see as one.
    @MainActor
    final class MessageRowTests: XCTestCase {
        private var app: XCUIApplication!

        override func setUp() async throws {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments = XCUIApplication.demoArguments
            app.launch()
            XCTAssertTrue(app.waitForStart(), "The app did not start")
            app.showPage("Packets")
        }

        func testTheRecipientFieldExplainsItself() {
            let message = app.textFields.matching(isMessage).firstMatch
            XCTAssertTrue(message.waitForExistence(timeout: 60), "No line to write a message")
            let recipient = app.textFields.matching(NSPredicate(format: "placeholderValue == 'To: all'")).firstMatch
            XCTAssertTrue(recipient.exists, "The recipient field does not say that empty sends to all")
            XCTAssertFalse(app.buttons["Explain"].firstMatch.exists, "The recipient field has a button to explain it")
        }

        func testSendIsAsTallAsTheMessageField() {
            let message = app.textFields.matching(isMessage).firstMatch
            XCTAssertTrue(message.waitForExistence(timeout: 60), "No line to write a message")
            let send = app.buttons["Send"].firstMatch
            XCTAssertTrue(send.exists)
            XCTAssertGreaterThanOrEqual(send.frame.height, message.frame.height, "Send is lower than the message field")
            XCTAssertGreaterThanOrEqual(send.frame.width, 44, "Send is too narrow for a finger")
        }

        private var isMessage: NSPredicate {
            NSPredicate(format: "label == 'Message' OR placeholderValue == 'Message'")
        }
    }
#endif
