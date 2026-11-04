import KV4PAudio
import KV4PProtocol
import KV4PTestSupport
import Testing

@testable import KV4PRadio

/// When other apps get quieter and when they get their sound back (ADR-0043).
@MainActor
@Suite("Other audio controller")
struct OtherAudioControllerTests {
    @MainActor
    final class Setup {
        let log = CallLog()
        let clock = ManualClock()
        let player = RXAudioPlayer(fadesIn: false)
        let session: FakeAudioSession
        let controller: OtherAudioController
        private let failureLog = CallLog()

        init(
            isOtherAudioPlaying: Bool = true,
            sessionFails: Bool = false,
            lowerFails: Bool = false,
            outputFails: Bool = false,
            prepareGate: AsyncStream<Void>? = nil
        ) {
            let log = log
            let clock = clock
            let session = FakeAudioSession(log: log, fails: sessionFails, lowerFails: lowerFails)
            session.isOtherAudioPlaying = isOtherAudioPlaying
            self.session = session
            let failureLog = failureLog
            controller = OtherAudioController(
                session: session,
                output: RecordingOutput(log: log, fails: outputFails),
                player: player,
                prepareMicrophone: {
                    log.append("prepare")
                    if let prepareGate {
                        for await _ in prepareGate { break }
                    }
                },
                reportFailure: { failureLog.append($0) },
                sleep: { try await clock.sleep(for: $0) }
            )
        }

        var calls: [String] { log.calls }

        var failures: [String] { failureLog.calls }

        func clearLog() { log.removeAll() }

        func until(_ expected: [String]) async -> Bool {
            await KV4PTestSupport.eventually { self.calls == expected }
        }

        /// Lets `duration` pass once a timer waits.
        func advance(by duration: Duration) async {
            await clock.waitForSleepers(1)
            clock.advance(by: duration)
        }

        /// Other apps are lowered, the log is empty.
        func lowered() async {
            controller.update(isBusy: true)
            #expect(await until(Self.lowering))
            clearLog()
        }

        /// The squelch closed long enough: other apps can come back, the session stays inactive.
        func released() async {
            await lowered()
            controller.update(isBusy: false)
            await advance(by: .seconds(3))
            #expect(await until(["stop", "release"]))
            clearLog()
        }

        static let lowering = ["stop", "lower pausePodcasts", "start", "prepare"]
        static let silencing = ["stop", "silence", "start", "prepare"]
        static let mixing = ["mix", "start", "prepare"]
    }

    @Test("while no other app plays, nothing switches, so nothing gets delayed")
    func nothingPlays() async {
        let setup = Setup(isOtherAudioPlaying: false)
        setup.controller.update(isBusy: true)
        await setup.controller.readyToTransmit()
        setup.controller.endKeying()
        setup.controller.update(isBusy: false)
        #expect(setup.calls.isEmpty)
    }

    @Test("Keep playing leaves other apps alone")
    func keepPlaying() async {
        let setup = Setup()
        setup.controller.mode = .keepPlaying
        setup.controller.update(isBusy: true)
        await setup.controller.readyToTransmit()
        #expect(setup.calls.isEmpty)
    }

    @Test("a signal stops the audio, lowers other apps in the chosen mode, then plays again")
    func lowers() async {
        let setup = Setup()
        setup.controller.mode = .lower
        setup.controller.update(isBusy: true)
        #expect(await setup.until(["stop", "lower lower", "start", "prepare"]))
    }

    @Test("repeated reports of the same signal switch once")
    func oncePerSignal() async {
        let setup = Setup()
        setup.controller.update(isBusy: true)
        setup.controller.update(isBusy: true)
        #expect(await setup.until(Setup.lowering))
        setup.controller.update(isBusy: true)
        await Task.yield()
        #expect(setup.calls == Setup.lowering)
    }

    @Test("after the set time without a signal, other apps get a moment to return before the session is active again")
    func handsBack() async {
        let setup = Setup()
        await setup.released()
        await setup.advance(by: .seconds(2))
        #expect(await setup.until(Setup.mixing))
    }

    @Test("the time to wait can be changed")
    func resumeAfter() async {
        let setup = Setup()
        setup.controller.resumeAfter = .seconds(5)
        await setup.lowered()
        setup.controller.update(isBusy: false)
        await setup.advance(by: .seconds(4))
        await Task.yield()
        #expect(setup.calls.isEmpty)
        setup.clock.advance(by: .seconds(1))
        #expect(await setup.until(["stop", "release"]))
    }

    @Test("a signal before the time is up keeps other apps lowered, and the time starts anew")
    func signalKeepsLowered() async {
        let setup = Setup()
        await setup.lowered()
        setup.controller.update(isBusy: false)
        await setup.clock.waitForSleepers(1)
        setup.controller.update(isBusy: true)
        setup.controller.update(isBusy: false)
        await setup.advance(by: .seconds(3))
        #expect(await setup.until(["stop", "release"]))
    }

    @Test("a signal while the session is inactive lowers other apps at once, without the wait")
    func signalWhileReleased() async {
        let setup = Setup()
        await setup.released()
        setup.controller.update(isBusy: true)
        #expect(await setup.until(["lower pausePodcasts", "start", "prepare"]))
    }

    @Test("a signal right after handing back lowers again, also before the other app has returned")
    func signalBeforeReturn() async {
        let setup = Setup()
        await setup.released()
        setup.session.isOtherAudioPlaying = false
        setup.controller.update(isBusy: true)
        #expect(await setup.until(["lower pausePodcasts", "start", "prepare"]))
    }

    @Test("with Keep playing chosen in the meantime, a signal only activates the session again")
    func signalAfterKeepPlaying() async {
        let setup = Setup()
        await setup.released()
        setup.controller.mode = .keepPlaying
        setup.controller.update(isBusy: true)
        #expect(await setup.until(Setup.mixing))
    }

    @Test("PTT pauses other apps entirely before the microphone opens, as lowered audio would still go on air")
    func transmitWaits() async {
        let setup = Setup()
        await setup.controller.readyToTransmit()
        #expect(setup.calls == Setup.silencing)
    }

    @Test("PTT with Lower all also pauses other apps")
    func transmitLowerAll() async {
        let setup = Setup()
        setup.controller.mode = .lower
        await setup.controller.readyToTransmit()
        #expect(setup.calls == Setup.silencing)
    }

    @Test("PTT during a signal switches from lowered to paused, as a lowered session may have no microphone")
    func transmitWhileLowered() async {
        let setup = Setup()
        await setup.lowered()
        setup.session.isOtherAudioPlaying = false  // a paused podcast does not count as playing
        await setup.controller.readyToTransmit()
        #expect(setup.calls == Setup.silencing)
    }

    @Test("PTT while the session is inactive pauses other apps before the microphone opens")
    func transmitWhileReleased() async {
        let setup = Setup()
        await setup.released()
        await setup.controller.readyToTransmit()
        #expect(setup.calls == ["silence", "start", "prepare"])
    }

    @Test("once paused, more PTT presses and signals switch nothing, until the time is up")
    func staysPaused() async {
        let setup = Setup()
        await setup.controller.readyToTransmit()
        setup.controller.endKeying()
        setup.clearLog()
        setup.controller.update(isBusy: true)
        await setup.controller.readyToTransmit()
        setup.controller.endKeying()
        #expect(setup.calls.isEmpty)
        setup.controller.update(isBusy: false)
        await setup.advance(by: .seconds(3))
        #expect(await setup.until(["stop", "release"]))
    }

    @Test("if other apps cannot be paused, PTT still gets the session and the radio stays audible")
    func silenceFails() async {
        let setup = Setup(lowerFails: true)
        await setup.controller.readyToTransmit()
        #expect(setup.calls == ["stop", "silence", "mix", "start", "prepare"])
    }

    @Test("PTT waits until the microphone is prepared again, as the switch ended the engine prepared before")
    func transmitWaitsForMicrophone() async {
        let (gate, opener) = AsyncStream.makeStream(of: Void.self)
        let setup = Setup(prepareGate: gate)
        let isReady = Box<Bool>()
        let press = Task {
            await setup.controller.readyToTransmit()
            isReady.value = true
        }
        #expect(await setup.until(Setup.silencing))
        await Task.yield()
        #expect(isReady.value == nil)
        opener.yield()
        await press.value
        #expect(isReady.value == true)
    }

    @Test("PTT that ends before transmitting lets the time run")
    func keyingEnds() async {
        let setup = Setup()
        await setup.controller.readyToTransmit()
        setup.clearLog()
        setup.controller.endKeying()
        await setup.advance(by: .seconds(3))
        #expect(await setup.until(["stop", "release"]))
    }

    @Test("during a transmission nothing switches back, however long it takes")
    func noSwitchWhileTransmitting() async {
        let setup = Setup()
        await setup.controller.readyToTransmit()
        setup.clearLog()
        setup.controller.update(isBusy: true)
        setup.controller.endKeying()
        await Task.yield()
        setup.clock.advance(by: .seconds(600))
        await Task.yield()
        #expect(setup.calls.isEmpty)
    }

    // MARK: Received audio

    static let second = [Int16](repeating: 1, count: KV4P.audioSampleRate)

    @Test("audio stays while the output is off; when it has played out, the silence behind it goes")
    func keepsAudio() async {
        let setup = Setup()
        setup.controller.update(isBusy: true)
        #expect(await setup.until(Setup.lowering))
        setup.player.receive(samples: Self.second)
        #expect(setup.player.statistics.buffered == KV4P.audioSampleRate)
        #expect(setup.player.statistics.droppedSamples == 0)

        setup.controller.update(isBusy: false)
        await setup.advance(by: .seconds(1))  // the audio in the buffer has played by now
        #expect(await KV4PTestSupport.eventually { setup.player.statistics.buffered == 0 })
        setup.clearLog()
        await setup.advance(by: .seconds(2))
        #expect(await setup.until(["stop", "release"]))
    }

    @Test("audio longer than the set time plays out before the session is released")
    func audioOutlastsTheTime() async {
        let setup = Setup()
        setup.controller.resumeAfter = .seconds(1)
        setup.controller.update(isBusy: true)
        #expect(await setup.until(Setup.lowering))
        setup.player.receive(samples: Self.second + Self.second[..<(KV4P.audioSampleRate / 2)])
        setup.clearLog()
        setup.controller.update(isBusy: false)
        await setup.clock.waitForSleepers(1)
        setup.clock.advance(by: .seconds(1))
        await Task.yield()
        #expect(setup.calls.isEmpty)
        setup.clock.advance(by: .milliseconds(500))
        #expect(await setup.until(["stop", "release"]))
    }

    @Test("what came in while the session was inactive is silence and goes when a signal starts")
    func discardsSilenceWhenReleased() async {
        let setup = Setup()
        await setup.released()
        setup.player.receive(samples: [1, 2, 3])
        setup.controller.update(isBusy: true)
        #expect(await setup.until(["lower pausePodcasts", "start", "prepare"]))
        #expect(setup.player.statistics.buffered == 0)
    }

    // MARK: Failures and stopping

    @Test("if other apps cannot be lowered, the radio stays audible")
    func lowerFails() async {
        let setup = Setup(lowerFails: true)
        setup.controller.update(isBusy: true)
        #expect(await setup.until(["stop", "lower pausePodcasts", "mix", "start", "prepare"]))
        #expect(setup.failures.isEmpty)
    }

    @Test("if the session cannot be activated at all, it is reported")
    func sessionFails() async {
        let setup = Setup(sessionFails: true)
        setup.controller.update(isBusy: true)
        #expect(await setup.until(["stop", "lower pausePodcasts", "mix", "start", "prepare"]))
        #expect(setup.failures == ["The audio output cannot be started."])
    }

    @Test("if the session cannot be activated after handing back, it is reported")
    func mixFails() async {
        let setup = Setup()
        await setup.released()
        setup.session.startFailing()
        await setup.advance(by: .seconds(2))
        #expect(await setup.until(Setup.mixing))
        #expect(setup.failures == ["The audio output cannot be started."])
    }

    @Test("if the output cannot start again, it is reported")
    func outputFails() async {
        let setup = Setup(outputFails: true)
        setup.controller.update(isBusy: true)
        #expect(await KV4PTestSupport.eventually { setup.failures == ["The audio output cannot be started."] })
    }

    @Test("stopping ends the timers, also for a waiting PTT, and the next signal starts over")
    func stops() async {
        let setup = Setup()
        await setup.lowered()
        await setup.controller.stop()
        setup.clock.advance(by: .seconds(600))
        await Task.yield()
        #expect(setup.calls.isEmpty)
        setup.controller.update(isBusy: true)
        #expect(await setup.until(Setup.lowering))
    }

    @Test("stopping during a switch waits for it and leaves nothing running")
    func stopsDuringSwitch() async {
        let setup = Setup()
        setup.controller.update(isBusy: true)
        await setup.controller.stop()
        #expect(setup.calls == Setup.lowering)
        setup.clock.advance(by: .seconds(600))
        await Task.yield()
        #expect(setup.calls == Setup.lowering)
    }

    // MARK: Interruptions

    @Test("after an interruption, other apps still get their sound back")
    func interruptionHandsBack() async {
        let setup = Setup()
        await setup.lowered()
        await setup.controller.interrupted()
        setup.controller.interruptionEnded(canResume: true)
        #expect(await setup.until(["stop", "release"]))
        await setup.advance(by: .seconds(2))
        #expect(await setup.until(["stop", "release"] + Setup.mixing))
    }

    @Test("an interruption that does not let the radio resume still hands back, and starts no audio")
    func interruptionNoResume() async {
        let setup = Setup()
        await setup.lowered()
        await setup.controller.interrupted()
        setup.controller.interruptionEnded(canResume: false)
        #expect(await setup.until(["release"]))
    }

    @Test("an interruption while other apps play next to the radio changes nothing")
    func interruptionWhileMixing() async {
        let setup = Setup()
        await setup.controller.interrupted()
        setup.controller.interruptionEnded(canResume: true)
        await Task.yield()
        #expect(setup.calls.isEmpty)
    }

    @Test("a connection that ends after an interruption has nothing left to hand back")
    func stopAfterInterruption() async {
        let setup = Setup()
        await setup.lowered()
        await setup.controller.interrupted()
        await setup.controller.stop()
        setup.controller.interruptionEnded(canResume: true)
        await Task.yield()
        #expect(setup.calls.isEmpty)
    }
}
