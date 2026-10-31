import KV4PProtocol
import Testing

@testable import KV4PSimulator

/// AX.25 transmit acceptance and received packets.
@Suite("Simulator packets")
struct PacketTests {
    static let packet: [UInt8] = Array(0x40..<0x60)

    @Test("KISS DATA is transmitted only with TX_ALLOWED")
    func kissDataNeedsTXAllowed() throws {
        var simulator = RadioSimulator()
        _ = simulator.receive(try FrameEncoder.ax25(Self.packet), at: .ms(10))
        #expect(simulator.transmittedPackets.isEmpty)
        _ = simulator.receive(FrameEncoder.desiredState(desiredState(sequence: 1, flags: [.txAllowed])), at: .ms(20))
        _ = simulator.receive(try FrameEncoder.ax25(Self.packet), at: .ms(30))
        #expect(simulator.transmittedPackets == [TransmittedPacket(packet: Self.packet, channel: nil)])
    }

    @Test("a packet on another frequency is transmitted if the module supports the frequency")
    func frequencyOverride() throws {
        var simulator = RadioSimulator()
        _ = simulator.receive(try FrameEncoder.ax25(Self.packet, onFrequency: 144.39, bandwidth: 1, ctcssTx: 0), at: .ms(10))
        _ = simulator.receive(try FrameEncoder.ax25(Self.packet, onFrequency: 433.5, bandwidth: 1, ctcssTx: 0), at: .ms(20))
        _ = simulator.receive(try FrameEncoder.ax25([], onFrequency: 144.39, bandwidth: 1, ctcssTx: 0), at: .ms(30))
        let channel = TransmittedPacket.Channel(freqTx: 144.39, bandwidth: 1, ctcssTx: 0)
        #expect(simulator.transmittedPackets == [TransmittedPacket(packet: Self.packet, channel: channel)])
    }

    @Test("an oversize frequency override is ignored")
    func oversizeOverride() {
        var simulator = RadioSimulator()
        let header = TransmittedPacket.Channel(freqTx: 144.39, bandwidth: 1, ctcssTx: 0).encodedForTest
        let packet = [UInt8](repeating: 0x41, count: KV4P.ax25MaxDataLength + 1)
        _ = simulator.receive(FrameEncoder.vendor(.txAX25, header + packet), at: .ms(10))
        #expect(simulator.transmittedPackets.isEmpty)
    }

    @Test("KISS parameters are recorded")
    func kissParameters() {
        var simulator = RadioSimulator()
        _ = simulator.receive(FrameEncoder.kissTxDelay(30) + [0xC0, 0x02, 0x3F, 0xC0], at: .ms(10))
        #expect(simulator.kissParameters == [.txDelay: 30, .persist: 0x3F])
    }

    @Test("a packet heard on air is sent to a connected host as KISS DATA")
    func heardPacket() throws {
        var simulator = RadioSimulator()
        #expect(simulator.hear(Self.packet, at: .ms(10)).isEmpty)
        _ = simulator.connect(at: .ms(20))
        #expect(try events(simulator.hear(Self.packet, at: .ms(30))) == [.ax25(Self.packet)])
        _ = simulator.disconnect(at: .ms(40))
        #expect(simulator.hear(Self.packet, at: .ms(50)).isEmpty)
    }
}

extension TransmittedPacket.Channel {
    /// The `HOST_TX_AX25` header, built through the encoder so its layout is not duplicated.
    var encodedForTest: [UInt8] {
        let frame = (try? FrameEncoder.ax25([], onFrequency: freqTx, bandwidth: bandwidth, ctcssTx: ctcssTx)) ?? []
        var parser = HostFrameParser()
        guard case .command(.txAX25, let header) = parser.process(frame).first?.content else { return [] }
        return header
    }
}
