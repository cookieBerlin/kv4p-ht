import SwiftUI

/// What the controls do, in one place: a tooltip on the Mac, a text or an info button on iPhone and iPad.
enum ControlHelp {
    static let meter =
        "S-meter: the strength of the received signal. The mark above it is the squelch level; weaker signals stay "
        + "muted; drag on the bars to change it, on iPhone and iPad after a short hold. The speaker icon shows whether "
        + "the squelch is open."
    static let frequency =
        "Scroll over a digit, or press ↑ or ↓ at the cursor, to step it in the channel raster; with ⌥ by the digit "
        + "exactly. Enter a frequency and press Return to tune to it."
    static let aprsPages =
        "The packets, the chats and the APRS settings. Off, the app also receives and sends no APRS: no beacons, "
        + "messages, acknowledgements, digipeating or APRS-IS. The other APRS settings stay for when it is on again."
    static let connectAtStart = "Connects to the radio chosen last when the app starts."
    static let scan = "Steps through the memories shown and stops on a signal."
    static let manageMemories = "Sort the memories and groups, change several at once and import repeaters."
    static let importRepeaterBook = "Adds repeaters from a CSV file exported from RepeaterBook."
    static let importDARC = "Adds FM repeaters and beacons from a CSV file exported from the DARC repeater lists."
    static let recipient = "The callsign to send to. Leave it empty to send a bulletin to everyone."
    static let bandwidth = "Use the bandwidth of the channel: 12.5 kHz is narrow FM, 25 kHz is wide FM."
    #if os(iOS)
        static let otherAudio =
            "What other apps do while the radio receives or you transmit. Podcast apps decide themselves whether they "
            + "continue."
    #else
        static let otherAudio = "What other apps do while the radio receives or you transmit."
    #endif
    static let muteAll = "Other apps keep running silently, so a video or podcast goes on without being heard."
    static let transmitWithCallsign = "The app can transmit, under this callsign."
    static let listenOnly =
        "The app does not transmit: no PTT, access tone, APRS messages, beacons or digipeating. With a callsign, the "
        + "iGate and the APRS-IS feed stay available."
    static let settingsSync =
        "Your callsign, memories, the PTT, access tone and APRS options and the frequency limits follow you to your "
        + "other devices with the same Apple ID. For memories, a change of this switch takes effect at the next start."
    static let accessTone =
        "Hold to send the tone that opens a repeater. It ends by itself; releasing it earlier stops it."
    static let squelch = "How strong a signal must be to be heard. 0 keeps the speaker always on."
    static let txTone = "A tone sent with your voice. Many repeaters open only with the right one."
    static let rxTone = "Hear only signals that carry this tone."
    static let highPower = "Reaches further, but uses more battery. Works on radios with a power switch."
    static let voiceMode = "FreeDV 2400B is digital voice. The other station must use it too."
    static let preEmphasis = "Raises high tones when sending and lowers them when receiving. FM usually uses it."
    static let highPass = "Removes low tones, such as CTCSS, from the sound."
    static let lowPass = "Removes high tones, such as hiss, from the sound."
    static let stickyPTT = "Press PTT once to start transmitting and again to stop, instead of holding it."
    static let micGain = "Makes a quiet microphone louder."
    static let frequencyLimits =
        "The app transmits only inside these frequencies. Set them to what your licence allows."
    static let beacon = "Sends your position now and then at the chosen interval while the radio is connected."
    static let beaconInterval = "All stations share the APRS frequency, so choose no more often than you need."
    static let backgroundBeacon =
        "Keeps sending with the screen locked. The system then shows its location indicator, and more battery is used."
    static let symbol = "The icon others see for your station on APRS maps."
    static let accuracy = "How accurately others see your position. Rounding it keeps your exact location private."
    static let beaconFrequency = "The frequency for your beacons; usually the APRS frequency of your region."
    static let units = "For temperature, wind, rain, snow and distances in the APRS list. Pressure stays in hPa."
    static let forMe = "Only messages from or to your callsign, with any SSID."
    static let packetTypes = "Shows only the chosen types of packet."
    static let exportPackets = "Saves the packets this list shows, also those stored, as a file."
    static let detailedLogging =
        "Also logs each packet by its kind, each scan step and the traffic per minute, without callsigns or text. Turns itself off after a day."
    static let notifyMessages =
        "A message to your callsign, with any SSID, brings a notification while the app is in the background."
    static let simulatedAnswer =
        "How the station you write to over the simulator answers: with an acknowledgement after 2 s, also with a reply, by rejecting it, or not at all, as to try Send again."
    static let simulatedReplyDelay =
        "Time to put the app in the background, to see the notification of the reply."
    static let keepMessages =
        "Messages to and from you, which the chats show, stay this long, apart from the other packets."
    static let keepPackets = "The APRS list stays when the app ends. The packets stay on this device."
    static let packetStored = "Stored: this packet stays when the app ends."
    static let packetNotStored = "Not stored: this packet goes when the app ends."
    static let keepInternetPackets =
        "Also keeps packets only from the internet, which can be many. Messages to or from you always stay."
    static let digipeat = "Sends on packets addressed to WIDE1-1 or your callsign, so they reach further."
    static let iGate = "Passes the packets you receive on to the APRS-IS internet network."
    static let internetFeed = "Adds packets from the APRS-IS internet network near your position to the list."
}

extension View {
    /// For a row with room below it: a short text below the row, on every platform (ADR-0048).
    func explained(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            self
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// For a control without room for a text: iPhone and iPad show the explanation on a tap. The Mac has the tooltip.
struct HelpButton: View {
    let text: String
    @State private var isShown = false

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        #if os(iOS)
            Button("Explain", systemImage: "info.circle") { isShown = true }
                .labelStyle(.iconOnly)
                .capsuleButton()
                .popover(isPresented: $isShown) {
                    Text(text)
                        .font(.footnote)
                        .padding()
                        .frame(idealWidth: 280)
                        .fixedSize(horizontal: false, vertical: true)
                        .presentationCompactAdaptation(.popover)
                }
        #endif
    }
}
