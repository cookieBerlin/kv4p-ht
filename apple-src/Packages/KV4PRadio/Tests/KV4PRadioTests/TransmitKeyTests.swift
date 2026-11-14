import KV4PTestSupport
import Testing

@testable import KV4PRadio

/// The Mac transmits while a key is held, as while its button is: PTT with the space bar, the access tone with ⌥ and the
/// space bar (ADR-0075).
@MainActor
@Suite("Transmit keys")
struct TransmitKeyTests {
    private typealias Setup = RadioViewModelAccessToneTests.Setup

    @Test("a key transmits only where its button can")
    func offered() async {
        let setup = Setup()
        let model = setup.model
        #expect(!model.canPress(.ptt))
        #expect(!model.canPress(.accessTone))
        await setup.connected()
        #expect(model.canPress(.ptt))
        #expect(!model.canPress(.accessTone))  // no tone set
        model.accessToneHz = 1750
        #expect(model.canPress(.accessTone))
        setup.permissions.set(.microphone, .denied)
        #expect(await RadioViewModelTests.eventually(model) { !$0.canPress(.ptt) && !$0.canPress(.accessTone) })
        setup.permissions.set(.microphone, .granted)
        #expect(await RadioViewModelTests.eventually(model) { $0.canPress(.ptt) })
        model.isListenOnly = true
        #expect(!model.canPress(.ptt))
        #expect(!model.canPress(.accessTone))
    }

    @Test("PTT transmits while its key is held, and the tone waits for it")
    func ptt() async {
        let setup = Setup()
        await setup.connected()
        setup.model.accessToneHz = 1750
        await setup.model.press(.ptt)
        #expect(setup.model.isTransmitting)
        #expect(!setup.model.canPress(.accessTone))
        await setup.model.release(.ptt)
        #expect(!setup.model.isTransmitting)
    }

    @Test("the tone goes out while its key is held, and PTT waits for it")
    func accessTone() async {
        let setup = Setup()
        await setup.connected()
        setup.model.accessToneHz = 1750
        let press = Task { await setup.model.press(.accessTone) }
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.isSendingAccessTone })
        #expect(!setup.model.canPress(.ptt))
        #expect(setup.model.canPress(.accessTone))
        await setup.model.release(.accessTone)
        await setup.run(until: press)
        #expect(!setup.model.isTransmitting)
    }
}
