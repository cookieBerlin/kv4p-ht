import KV4PProtocol
import Testing

@testable import KV4PAudio

/// The tone that opens a repeater (ADR-0045).
@Suite("Access tone")
struct AccessToneTests {
    static func crossings(_ samples: [Int16]) -> Int {
        zip(samples, samples.dropFirst()).count { $0 < 0 && $1 >= 0 }
    }

    @Test("the choices are those of the settings")
    func choices() {
        #expect(AccessTone.frequencies == [1000, 1450, 1750, 2100])
        #expect(AccessTone.lengthsMs == [250, 500, 1000, 2000, 3000, 4000, 5000])
        #expect(AccessTone.waitsMs == [0, 100, 200, 300, 500, 1000])
        #expect(AccessTone.defaultLengthMs == 1000)
        #expect(AccessTone.defaultWaitMs == 200)
    }

    @Test("the lengths read as seconds")
    func lengthLabels() {
        #expect(
            AccessTone.lengthsMs.map(AccessTone.lengthLabel) == ["0.25 s", "0.5 s", "1 s", "2 s", "3 s", "4 s", "5 s"]
        )
    }

    @Test("the time becomes samples at the rate of the radio")
    func durations() {
        let tone = AccessTone(frequency: 1750, lengthMs: 500, waitMs: 200)
        #expect(tone.samples().count == KV4P.audioSampleRate / 2)
        #expect(tone.waitSamples == KV4P.audioSampleRate / 5)
    }

    @Test(
        "each tone has its frequency",
        arguments: AccessTone.frequencies
    )
    func frequency(hertz: Int) {
        let samples = AccessTone(frequency: hertz, lengthMs: 1000, waitMs: 0).samples()
        #expect(abs(Self.crossings(samples) - hertz) <= 1)
    }

    @Test("the level is half of full scale")
    func level() {
        let samples = AccessTone(frequency: 1750, lengthMs: 250, waitMs: 0).samples()
        let peak = samples.map { abs(Int($0)) }.max() ?? 0
        #expect((16300...16384).contains(peak))
    }

    @Test("it starts and ends at silence, without a click")
    func edges() {
        let samples = AccessTone(frequency: 1750, lengthMs: 250, waitMs: 0).samples()
        #expect(abs(Int(samples[0])) < 100)
        #expect(abs(Int(samples[samples.count - 1])) < 100)
    }
}
