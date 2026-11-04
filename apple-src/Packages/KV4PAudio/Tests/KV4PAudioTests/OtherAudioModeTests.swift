import Testing

@testable import KV4PAudio

@Suite("Other audio mode")
struct OtherAudioModeTests {
    @Test("only keeping them playing warns that they can go on air")
    func warnings() {
        #expect(
            OtherAudioMode.keepPlaying.warning
                == "Other apps also keep playing while you transmit. The microphone can pick them up and send them on air."
        )
        #expect(OtherAudioMode.lower.warning == nil)
        #expect(OtherAudioMode.pausePodcasts.warning == nil)
    }

    @Test("each mode names itself, and only keeping them playing leaves other apps alone")
    func labels() {
        #expect(OtherAudioMode.allCases.map(\.label) == ["Keep playing", "Lower all", "Pause podcasts, lower music"])
        #expect(OtherAudioMode.allCases.map(\.changesOtherAudio) == [false, true, true])
    }
}
