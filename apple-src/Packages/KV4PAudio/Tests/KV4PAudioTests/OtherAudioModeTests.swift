import Testing

@testable import KV4PAudio

@Suite("Other audio mode")
struct OtherAudioModeTests {
    @Test("each mode names itself, and only keeping them playing leaves other apps alone")
    func labels() {
        #expect(OtherAudioMode.allCases.map(\.label) == ["Keep playing", "Lower all", "Pause podcasts, lower music"])
        #expect(OtherAudioMode.allCases.map(\.changesOtherAudio) == [false, true, true])
    }
}
