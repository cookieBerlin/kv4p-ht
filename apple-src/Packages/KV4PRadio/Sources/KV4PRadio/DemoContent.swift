import Foundation
import KV4PPersistence

/// What the app shows in its demo mode, so that the accessibility audit finds every screen filled (ADR-0062).
/// Placeholders only.
public enum DemoContent {
    public static let memories = [
        ChannelMemory(name: "Calling channel", frequency: 145.5),
        ChannelMemory(
            name: "Repeater",
            frequency: 145.6,
            offset: .down,
            txTone: "88.5",
            group: "Repeaters",
            accessToneHz: 1750
        ),
        ChannelMemory(name: "APRS", frequency: 144.8, group: "Digital"),
    ]

    /// Every kind of packet the list shows, and two chats, one of them unread.
    public static let aprsLines = [
        "N1CALL>APRS,TCPIP*:=4903.50N/07201.75W>Mobile station",
        "N1CALL>APRS,TCPIP*:;OBJECT   *111111z4903.50N/07201.75W-Test object",
        "N1CALL>APRS,TCPIP*:=4903.50N/07201.75W_220/004g005t077r000p000P000h50b09900",
        "N1CALL>APRS,TCPIP*:>On the air",
        "N1CALL>APRS,TCPIP*::N0CALL   :Hello from the demo{1",
        "N0CALL>APRS,TCPIP*::N1CALL   :Hello back{2",
        "N2CALL-7>APRS,TCPIP*::N0CALL   :Are you there?{3",
        "N1CALL>APRS,TCPIP*::BLN1CQ   :A bulletin to all",
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
