import KV4PAudio
import KV4PProtocol

/// Lowers other apps while the radio receives or transmits, and hands their sound back afterwards (ADR-0043).
///
/// PTT pauses all other apps instead: lowered audio from the speaker would go on air, and a session that pauses only
/// podcasts has no microphone.
///
/// Each switch needs the session to be inactive, so the output stops for up to a second. Received audio waits in the
/// player's buffer meanwhile. After handing back, the session stays inactive for a moment: a podcast app returns only
/// then.
@MainActor
final class OtherAudioController {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private enum Phase {
        /// Other apps play next to the radio, as usual.
        case mixing
        /// Other apps are lowered, or podcasts paused. The microphone may not be available.
        case lowered
        /// All other apps are paused, and the microphone is available, for a transmission.
        case silenced
        /// The session is inactive, so that other apps can return.
        case released
    }

    /// A podcast app was back after about 1.15 s in the tests on an iPhone.
    static let podcastReturnWait: Duration = .seconds(2)
    private static let audioFailure = "The audio output cannot be started."

    var mode = OtherAudioMode.pausePodcasts
    var resumeAfter: Duration = .seconds(3)

    private let diagnostics: DiagnosticLog?
    private let session: any OtherAudioSwitching
    private let output: (any AudioOutput)?
    private let player: RXAudioPlayer
    private let prepareMicrophone: () async -> Void
    private let reportFailure: (String) -> Void
    private let sleep: Sleep
    /// How long other apps get to come back before the session is active again.
    private let releaseWait: Duration

    private var phase = Phase.mixing
    private var isBusy = false
    /// An interruption ended what this controller would have handed back.
    private var owesHandBack = false
    /// PTT is waiting to open the microphone.
    private var isKeying = false
    /// The switch being made; there is only ever one.
    private var step: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(
        session: any OtherAudioSwitching,
        output: (any AudioOutput)?,
        player: RXAudioPlayer,
        prepareMicrophone: @escaping () async -> Void,
        reportFailure: @escaping (String) -> Void,
        sleep: @escaping Sleep,
        releaseWait: Duration = OtherAudioController.podcastReturnWait,
        diagnostics: DiagnosticLog? = nil
    ) {
        self.diagnostics = diagnostics
        self.session = session
        self.output = output
        self.player = player
        self.prepareMicrophone = prepareMicrophone
        self.reportFailure = reportFailure
        self.sleep = sleep
        self.releaseWait = releaseWait
    }

    /// The radio receives something to play, or transmits.
    func update(isBusy: Bool) {
        if isBusy != self.isBusy {
            note(isBusy ? "busy" : "not busy")
        }
        self.isBusy = isBusy
        advance()
    }

    /// Returns once the microphone can open: other apps are paused if they play, so they do not go on air.
    func readyToTransmit() async {
        isKeying = true
        advance()
        guard step != nil else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// PTT no longer waits; `update(isBusy:)` covers a transmission that started.
    func endKeying() {
        isKeying = false
        advance()
    }

    /// Ends all timers and a running switch, for a connection that ends or an interrupted session.
    func stop() async {
        note("stop")
        isBusy = false
        isKeying = false
        owesHandBack = false
        await step?.value
        timer?.cancel()
        timer = nil
        phase = .mixing
        player.holdAudio(false)
        resumeWaiters()
    }

    /// The system took the audio. Other apps that this app lowered or paused still wait for their sound.
    func interrupted() async {
        await step?.value  // a switch may be under way
        let owesHandBack = phase != .mixing
        await stop()
        self.owesHandBack = owesHandBack
    }

    /// The system gave the audio back. Without `canResume` the radio stays silent, but other apps can go on.
    func interruptionEnded(canResume: Bool) {
        guard owesHandBack else { return }
        owesHandBack = false
        if canResume {
            run { await self.release() }
        } else {
            run { await self.session.releaseOtherAudio() }
        }
    }

    private func advance() {
        guard step == nil else { return }
        let isWanted = isBusy || isKeying
        switch phase {
        case .mixing:
            if isWanted, mode.changesOtherAudio, session.isOtherAudioPlaying {
                run {
                    self.holdAudio(true)
                    self.output?.stop()
                    await self.quietOthers()
                }
            }
        case .lowered where isKeying:
            timer?.cancel()
            timer = nil
            run {
                self.holdAudio(true)
                self.output?.stop()
                await self.silence()
            }
        case .lowered, .silenced:
            if isWanted {
                timer?.cancel()
                timer = nil
            } else if timer == nil {
                startHandBackTimer()
            }
        case .released:
            if isWanted {
                timer?.cancel()
                timer = nil
                run { await self.returnFromRelease() }
            }
        }
        if step == nil {
            resumeWaiters()
        }
    }

    private func note(_ step: String) {
        diagnostics?.log(.info, .audio, "Other audio: \(step), playing=\(session.isOtherAudioPlaying)")
    }

    private func run(_ body: @escaping @MainActor () async -> Void) {
        step = Task {
            await body()
            step = nil
            advance()
        }
    }

    private func resumeWaiters() {
        let resumed = waiters
        waiters = []
        resumed.forEach { $0.resume() }
    }

    /// What the moment asks for: PTT needs other apps paused, a signal only lowered.
    private func quietOthers() async {
        if isKeying {
            await silence()
        } else {
            await lower()
        }
    }

    private func lower() async {
        note("lower \(mode.rawValue)")
        do {
            try await session.lowerOtherAudio(mode)
        } catch {
            note("lowering failed, \(DiagnosticLog.describe(error))")
            await mix()
        }
        await restartOutput()
        phase = .lowered
    }

    private func silence() async {
        note("pause all")
        do {
            try await session.silenceOtherAudio()
        } catch {
            note("pausing failed, \(DiagnosticLog.describe(error))")
            await mix()
        }
        await restartOutput()
        phase = .silenced
    }

    /// The audio that waits still has to play; what follows it is the silence of a closed squelch.
    private func startHandBackTimer() {
        let lag =
            output == nil ? .zero : Duration.seconds(Double(player.statistics.buffered) / Double(KV4P.audioSampleRate))
        let rest = resumeAfter - lag
        timer = Task {
            do {
                if lag > .zero {
                    try await sleep(lag)
                }
                discardWaitingAudio()
                holdAudio(false)
                if rest > .zero {
                    try await sleep(rest)
                }
            } catch {
                return  // cancelled
            }
            timer = nil
            run { await self.release() }
        }
    }

    private func release() async {
        note("hand back")
        output?.stop()
        await session.releaseOtherAudio()
        phase = .released
        timer = Task {
            guard (try? await sleep(releaseWait)) != nil else { return }  // cancelled
            timer = nil
            run {
                self.discardWaitingAudio()
                await self.mix()
                await self.restartOutput()
                self.phase = .mixing
            }
        }
    }

    /// A signal or PTT during the wait. What came in so far is silence; the other app may not be back yet, and lowering
    /// now keeps it from returning into the signal.
    private func returnFromRelease() async {
        discardWaitingAudio()
        guard mode.changesOtherAudio else {
            await mix()
            await restartOutput()
            phase = .mixing
            return
        }
        holdAudio(true)
        await quietOthers()
    }

    /// Only an output that stops makes audio wait; without one, the normal latency stays.
    private func holdAudio(_ isHolding: Bool) {
        if output != nil {
            player.holdAudio(isHolding)
        }
    }

    private func discardWaitingAudio() {
        if output != nil {
            player.discardBuffered()
        }
    }

    private func mix() async {
        note("mix again")
        do {
            try await session.mixWithOtherAudio()
        } catch {
            reportFailure(Self.audioFailure)
        }
    }

    /// Every switch stops the engines, and the microphone needs a new one that is prepared.
    private func restartOutput() async {
        do {
            try output?.start(player)
        } catch {
            reportFailure(Self.audioFailure)
        }
        await prepareMicrophone()
    }
}
