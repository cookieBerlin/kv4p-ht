import XCTest

/// The frequency steps by the raster: with − and + on iPhone and iPad, with ↑ and ↓ in the field on the Mac (ADR-0064).
@MainActor
final class FrequencyInputTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        connectToWindowServer()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-demo"]
        app.launch()
    }

    func testStepsUpAndDownByTheRaster() throws {
        let field = app.textFields["frequency"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 60), "No frequency field")
        XCTAssertTrue(waitUntilEnabled(field), "The demo radio did not connect")
        #if os(macOS)
            app.closeAbout()
        #endif
        // On a memory, its name stands above the frequency, and a step leaves the memory.
        let memory = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH 'Calling channel' OR value BEGINSWITH 'Calling channel'")
        )
        .firstMatch
        XCTAssertTrue(memory.waitForExistence(timeout: 5), "No memory to tune to")
        #if os(macOS)
            memory.click()
        #else
            memory.tap()
        #endif
        XCTAssertEqual(try waitForChange(of: field, to: 145.5), 145.5, accuracy: 0.000_01)
        let top = field.frame.minY
        let start = try megahertz(field)
        #if os(macOS)
            field.click()
            field.typeKey(.rightArrow, modifierFlags: .command)
            field.typeKey(.upArrow, modifierFlags: [])
        #else
            app.buttons["frequency-up"].firstMatch.tap()
        #endif
        let up = try waitForChange(of: field, from: start)
        XCTAssertEqual(field.frame.minY, top, accuracy: 0.5, "The frequency moved as the name of the memory went")
        let step = up - start
        XCTAssertTrue(abs(step - 0.0125) < 0.000_01 || abs(step - 0.025) < 0.000_01, "A step of \(step) MHz")
        #if os(macOS)
            field.typeKey(.downArrow, modifierFlags: [])
        #else
            app.buttons["frequency-down"].firstMatch.tap()
        #endif
        XCTAssertEqual(try waitForChange(of: field, from: up), start, accuracy: 0.000_01)
    }

    private func megahertz(_ field: XCUIElement) throws -> Double {
        let text = (field.value as? String ?? "").replacing(",", with: ".")
        return try XCTUnwrap(Double(text), "The field shows \(text)")
    }

    private func waitForChange(of field: XCUIElement, from old: Double) throws -> Double {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let new = try? megahertz(field), abs(new - old) > 0.000_01 { return new }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTFail("The frequency stayed at \(old) MHz")
        return old
    }

    private func waitForChange(of field: XCUIElement, to expected: Double) throws -> Double {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let new = try? megahertz(field), abs(new - expected) < 0.000_01 { return new }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return try megahertz(field)
    }

    private func waitUntilEnabled(_ element: XCUIElement) -> Bool {
        let enabled = NSPredicate(format: "isEnabled == true")
        return XCTWaiter.wait(for: [expectation(for: enabled, evaluatedWith: element)], timeout: 60) == .completed
    }
}
