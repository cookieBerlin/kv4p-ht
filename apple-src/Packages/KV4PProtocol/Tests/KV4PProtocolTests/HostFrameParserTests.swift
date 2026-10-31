import Testing

@testable import KV4PProtocol

/// Checks the device-side parser against the frames written by the Android `Protocol.Sender`
/// and against the firmware `KissParser` window accounting.
@Suite("Host frame parser")
struct HostFrameParserTests {
    static let senderFrames: [(name: String, frame: [UInt8])] = FrameEncoderVectorTests.vectors.flatMap { vector in
        (vector.expected.frames ?? []).compactMap { hex in (try? [UInt8](hex: hex)).map { (vector.name, $0) } }
    }

    @Test("every Android sender frame is parsed once and acknowledged with its encoded length")
    func androidSenderFrames() {
        #expect(!Self.senderFrames.isEmpty)
        for (name, frame) in Self.senderFrames {
            var parser = HostFrameParser()
            let parsed = parser.process(frame)
            #expect(parsed.map(\.encodedLength) == [frame.count], "\(name)")
            if let content = parsed.first?.content {
                #expect(reencode(content) == frame, "\(name)")
            } else {
                #expect(frame == [KISS.fend, KISS.Command.data, KISS.fend], "\(name)")
            }
        }
    }

    @Test("byte-by-byte input yields the same frames")
    func byteByByte() {
        let stream = Self.senderFrames.flatMap(\.frame)
        var whole = HostFrameParser()
        var split = HostFrameParser()
        #expect(stream.flatMap { split.process([$0]) } == whole.process(stream))
    }

    @Test("bytes before the first FEND are neither parsed nor acknowledged")
    func garbageBeforeFirstFEND() {
        var parser = HostFrameParser()
        #expect(parser.process([0x01, 0x02, 0xC0, 0x00, 0x41, 0xC0]) == [.init(content: .ax25([0x41]), encodedLength: 4)])
    }

    @Test("frames sharing one FEND are each acknowledged with both FENDs")
    func sharedFEND() {
        var parser = HostFrameParser()
        #expect(
            parser.process([0xC0, 0x00, 0x41, 0xC0, 0x00, 0x42, 0x43, 0xC0]) == [
                .init(content: .ax25([0x41]), encodedLength: 4),
                .init(content: .ax25([0x42, 0x43]), encodedLength: 5),
            ]
        )
    }

    @Test("empty frames are not acknowledged")
    func emptyFrames() {
        var parser = HostFrameParser()
        #expect(parser.process([0xC0, 0xC0, 0xC0]).isEmpty)
    }

    @Test("dropped frames are not acknowledged, as in the firmware")
    func droppedFrames() {
        var parser = HostFrameParser()
        let oversize = [0xC0, 0x00] + [UInt8](repeating: 0x41, count: KV4P.maxFrameSize) + [0xC0]
        #expect(parser.process([0xC0, 0x00, 0xDB, 0x01, 0xC0]).isEmpty)
        #expect(parser.process(oversize).isEmpty)
    }

    @Test(
        "frames the firmware ignores are still acknowledged",
        arguments: [
            [0xC0, 0x10, 0x41, 0xC0],  // port 1
            [0xC0, 0x00] + [UInt8](repeating: 0x41, count: KV4P.ax25MaxDataLength + 1) + [0xC0],
            [0xC0, 0x01, 0x05, 0x06, 0xC0],  // TXDELAY with two bytes
            [0xC0, 0x04, 0x01, 0xC0],  // TXTAIL is not handled
            [0xC0, 0x06] + Array("KV4Q".utf8) + [0x01, 0x0D, 0xC0],
            [0xC0, 0x06] + Array("KV4P".utf8) + [0x02, 0x0D, 0xC0],
            [0xC0, 0x06] + Array("KV4P".utf8) + [0x01, 0x7F, 0xC0],
            [0xC0, 0x06] + Array("KV4P".utf8) + [0xC0],
        ] as [[UInt8]]
    )
    func ignoredFrames(frame: [UInt8]) {
        var parser = HostFrameParser()
        #expect(parser.process(frame) == [.init(content: nil, encodedLength: frame.count)])
    }

    @Test("KISS PERSIST and SLOTTIME are parsed like TXDELAY")
    func kissParameters() {
        var parser = HostFrameParser()
        #expect(
            parser.process([0xC0, 0x02, 0x3F, 0xC0, 0xC0, 0x03, 0x0A, 0xC0]).map(\.content) == [
                .kissParameter(.persist, value: 0x3F),
                .kissParameter(.slotTime, value: 0x0A),
            ]
        )
    }

    /// Inverse of the parser, built from the host encoder so expectations are not duplicated.
    private func reencode(_ content: HostFrame) -> [UInt8] {
        switch content {
        case .ax25(let packet):
            (try? FrameEncoder.ax25(packet)) ?? []
        case .kissParameter(let parameter, let value):
            KISS.frame(command: parameter.rawValue, payload: [value])
        case .command(let command, let payload):
            FrameEncoder.vendor(command, payload)
        }
    }
}
