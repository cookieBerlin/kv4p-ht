import Foundation
import KV4PPersistence

/// What the app shows in its demo mode, so that the accessibility audit finds every screen filled (ADR-0062).
/// Placeholders only.
public enum DemoContent {
    public static let memories = [
        // A meeting point, for the frequencies on the map.
        ChannelMemory(name: "Calling channel", frequency: 145.5, latitude: 49.02, longitude: -72.08),
        ChannelMemory(
            name: "Local repeater",
            frequency: 145.6,
            offset: .down,
            txTone: "88.5",
            group: "Repeaters",
            accessToneHz: 1750,
            kind: .repeater,
            comment: "Example repeater",
            latitude: 49.058_33,
            longitude: -72.029_17
        ),
        ChannelMemory(
            name: "Local beacon",
            frequency: 144.49,
            group: "Repeaters",
            kind: .beacon,
            latitude: 49.1,
            longitude: -71.98
        ),
        ChannelMemory(
            name: "Hilltop repeater",
            frequency: 145.725,
            offset: .down,
            txTone: "100.0",
            group: "Repeaters",
            kind: .repeater,
            comment: "Wide coverage",
            latitude: 49.083_33,
            longitude: -71.95
        ),
        ChannelMemory(
            name: "Lake repeater",
            frequency: 145.65,
            offset: .down,
            txTone: "88.5",
            group: "Repeaters",
            kind: .repeater,
            latitude: 48.991_67,
            longitude: -72.116_67
        ),
        ChannelMemory(
            name: "Valley repeater",
            frequency: 145.775,
            offset: .down,
            txTone: "123.0",
            group: "Repeaters",
            kind: .repeater
        ),
        ChannelMemory(name: "Simplex 1", frequency: 145.55, group: "Simplex"),
        ChannelMemory(name: "Simplex 2", frequency: 145.525, group: "Simplex"),
        ChannelMemory(name: "Hiking net", frequency: 145.575, group: "Simplex", comment: "Sundays at 9 am"),
        ChannelMemory(name: "FreeDV", frequency: 145.45, group: "Digital", comment: "FreeDV 2400B"),
        // For 70 cm: the demo radio is one for 2 m, so the list hides it and says so.
        ChannelMemory(name: "Far repeater", frequency: 439.1, offset: .down, offsetKHz: 7600, kind: .repeater),
        ChannelMemory(name: "APRS", frequency: 144.8, group: "Digital"),
    ]

    /// Every kind of packet the list shows, and two chats, one of them unread. The stations stand around the memories'
    /// repeaters, each at a place of its own, so that the map shows them apart; the screenshots show all of it.
    public static let aprsLines = [
        "N1CALL>APRS,TCPIP*:=4903.50N/07201.75W>Mobile station",
        "N1CALL>APRS,TCPIP*:;OBJECT   *111111z4902.10N/07204.30W-Test object",
        "N4CALL-13>APRS,TCPIP*:=4900.80N/07203.40W_220/004g005t077r000p000P000h50b09900",
        "N3CALL-9>APRS,WIDE1-1:=4904.20N/07158.90W>On the way home",
        "N5CALL-1>APRS,TCPIP*:!4904.90N/07155.00W#Fill-in digipeater",
        "N6CALL-7>APRS,WIDE1-1:=4901.50N/07206.20W[Hiking the north trail",
        "N7CALL>APRS,TCPIP*:=4905.80N/07157.40W-Home station",
        "N1CALL>APRS,TCPIP*:>On the air",
        "N1CALL>APRS,TCPIP*::N0CALL   :GM OM! QRV on the hilltop rpt tonight?{1",
        "N0CALL>APRS,TCPIP*::N1CALL   :GM! Yes, QRV from 7 pm with the kv4p HT{2",
        "N1CALL>APRS,TCPIP*::N0CALL   :FB, will call you on 145.725. WX looks good{3",
        "N0CALL>APRS,TCPIP*::N1CALL   :TNX, CU on the rpt. 73{4",
        "N1CALL>APRS,TCPIP*::N0CALL   :73 es CUL{5",
        "N2CALL-7>APRS,TCPIP*::N0CALL   :QRV for a QSO on 145.550?{3",
        "N1CALL>APRS,TCPIP*::BLN1CQ   :Net tonight 8 pm on the hilltop rpt",
    ]
}

extension RadioViewModel {
    /// Fills the app for the demo mode; a second time adds nothing.
    public func loadDemoContent() async {
        guard memories.isEmpty else { return }
        for memory in DemoContent.memories {
            await save(memory)
        }
        receiveDemo(DemoContent.aprsLines)
    }
}
