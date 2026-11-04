import SwiftUI

/// What the controls do, in one place: a tooltip on the Mac, a text or an info button on iPhone and iPad.
enum ControlHelp {
    static let meter =
        "S-meter: the strength of the received signal. The mark above it is the squelch level; weaker signals stay "
        + "muted. The speaker icon shows whether the squelch is open."
    static let scan = "Steps through the memories shown and stops on a signal."
    static let manageMemories = "Sort the memories and groups, change several at once and import repeaters."
    static let importCSV = "Adds repeaters from a CSV file exported from RepeaterBook."
    static let recipient = "The callsign to send to. Leave it empty to send a bulletin to everyone."
    static let bandwidth = "Use the bandwidth of the channel: 12.5 kHz is narrow FM, 25 kHz is wide FM."
    #if os(iOS)
        static let otherAudio =
            "What other apps do while the radio receives or you transmit. Podcast apps decide themselves whether they "
            + "continue."
    #else
        static let otherAudio = "What other apps do while the radio receives or you transmit."
    #endif
    static let muteAll =
        "While other apps are muted, macOS can show a recording dot in the menu bar. The app records nothing, and "
        + "muting also works if you refuse System Audio Recording. If other apps stay audible, allow it under "
        + "Privacy & Security."
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
    static let beacon = "Sends your position now and every five minutes while the radio is connected."
    static let symbol = "The icon others see for your station on APRS maps."
    static let accuracy = "How accurately others see your position. Rounding it keeps your exact location private."
    static let beaconFrequency = "The frequency for your beacons; usually the APRS frequency of your region."
    static let digipeat = "Sends on packets addressed to WIDE1-1 or your callsign, so they reach further."
    static let iGate = "Passes the packets you receive on to the APRS-IS internet network."
    static let internetFeed = "Adds packets from the APRS-IS internet network near your position to the list."
}

extension View {
    /// For a row with room below it: a tooltip on the Mac, a short text below the row on iPhone and iPad.
    @ViewBuilder func explained(_ text: String) -> some View {
        #if os(macOS)
            help(text)
        #else
            VStack(alignment: .leading, spacing: 4) {
                self
                Text(text).font(.footnote).foregroundStyle(.secondary)
            }
        #endif
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
