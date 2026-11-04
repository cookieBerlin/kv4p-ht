import KV4PAPRS
import KV4PAudio
import KV4PProtocol
import KV4PRadio
import KV4PSimulator
import SwiftUI

/// The pages of the settings (ADR-0048), in the order the overview shows them.
enum SettingsPage: CaseIterable, Identifiable {
    case station, radio, transmit, audio, aprs, memories, simulator, advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .station: "Station"
        case .radio: "Radio"
        case .transmit: "Transmit"
        case .audio: "Audio"
        case .aprs: "APRS"
        case .memories: "Memories"
        case .simulator: "Simulator"
        case .advanced: "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .station: "person.crop.circle"
        case .radio: "antenna.radiowaves.left.and.right"
        case .transmit: "mic"
        case .audio: "speaker.wave.2"
        case .aprs: "location"
        case .memories: "list.bullet"
        case .simulator: "testtube.2"
        case .advanced: "slider.horizontal.3"
        }
    }
}

/// Your callsign and whether the app may transmit (ADR-0047).
struct StationSettings: View {
    @Bindable var model: RadioViewModel
    /// The callsign as typed; the model keeps it normalised in the settings.
    @State private var callsign = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("Your callsign") {
                    TextField("Your callsign", text: $callsign, prompt: Text("Enter callsign"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        #endif
                        .onChange(of: callsign) { model.callsign = callsign }
                }
                if let warning = model.stationWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Toggle("Listen only", isOn: $model.isListenOnly)
                    .explained(ControlHelp.listenOnly)
            }
        }
        .onAppear { callsign = model.callsign }
        .onChange(of: model.callsign) { callsign = model.callsign }
    }
}

/// A section that needs a radio; without one, it stays and says so.
private struct RadioSection<Rows: View>: View {
    let title: String
    let model: RadioViewModel
    @ViewBuilder let rows: Rows

    var body: some View {
        Section(title) {
            if model.isReady {
                rows
            } else {
                Text("Not available while no radio is connected.").foregroundStyle(.secondary)
            }
        }
    }
}

/// What the radio itself does: its channel, its audio filters and its firmware.
struct RadioSettings: View {
    @Bindable var model: RadioViewModel

    var body: some View {
        Form {
            RadioSection(title: "Channel", model: model) {
                Picker("Bandwidth", selection: $model.isWideBandwidth) {
                    Text("12.5 kHz").tag(false)
                    Text("25 kHz").tag(true)
                }
                .explained(ControlHelp.bandwidth)
                Stepper("Squelch \(model.squelch)", value: $model.squelch, in: 0...8)
                    .explained(ControlHelp.squelch)
                if let warning = model.squelchWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Picker("TX tone (CTCSS)", selection: $model.txTone) {
                    ForEach(CTCSS.labels, id: \.self) { Text($0) }
                }
                .explained(ControlHelp.txTone)
                Picker("RX tone (CTCSS)", selection: $model.rxTone) {
                    ForEach(CTCSS.labels, id: \.self) { Text($0) }
                }
                .explained(ControlHelp.rxTone)
                Toggle("High power", isOn: $model.isHighPower)
                    .explained(ControlHelp.highPower)
                Picker("Voice mode", selection: $model.isFreeDV) {
                    Text("Analog").tag(false)
                    Text("FreeDV 2400B").tag(true)
                }
                .disabled(!model.supportsFreeDV)
                .explained(ControlHelp.voiceMode)
                if !model.supportsFreeDV {
                    Text("The firmware of this radio has no FreeDV 2400B modem.").foregroundStyle(.secondary)
                }
            }
            RadioSection(title: "Audio filters", model: model) {
                Toggle("Pre-emphasis", isOn: $model.filters.preEmphasis)
                    .explained(ControlHelp.preEmphasis)
                Toggle("High-pass", isOn: $model.filters.highPass)
                    .explained(ControlHelp.highPass)
                Toggle("Low-pass", isOn: $model.filters.lowPass)
                    .explained(ControlHelp.lowPass)
            }
            if model.firmwareText != nil || model.canUpdateFirmware || model.firmwareUpdate != .idle {
                Section("Firmware") {
                    if let firmware = model.firmwareText {
                        Text(firmware).foregroundStyle(.secondary)
                    }
                    if model.canUpdateFirmware || model.firmwareUpdate != .idle {
                        FirmwareUpdateRow(model: model)
                    }
                }
            }
        }
    }
}

/// How the app transmits, and the tone that opens a repeater (ADR-0045); a memory can have its own tone.
struct TransmitSettings: View {
    @Bindable var model: RadioViewModel

    var body: some View {
        Form {
            RadioSection(title: "Transmit", model: model) {
                Toggle("Sticky PTT", isOn: $model.isStickyPTT)
                    .explained(ControlHelp.stickyPTT)
                Picker("Mic gain boost", selection: $model.micGain) {
                    ForEach(MicGain.allCases, id: \.self) { Text($0.label) }
                }
                .explained(ControlHelp.micGain)
            }
            Section("Repeater access tone") {
                Picker("Tone", selection: $model.accessToneHz) {
                    Text("Off").tag(0)
                    ForEach(AccessTone.frequencies, id: \.self) { Text("\($0) Hz").tag($0) }
                }
                .explained(ControlHelp.accessTone)
                if model.accessToneHz > 0 {
                    Picker("Length", selection: $model.accessToneLengthMs) {
                        ForEach(AccessTone.lengthsMs, id: \.self) { Text(AccessTone.lengthLabel($0)).tag($0) }
                    }
                    Picker("Wait before the tone", selection: $model.accessToneWaitMs) {
                        ForEach(AccessTone.waitsMs, id: \.self) { Text("\($0) ms").tag($0) }
                    }
                }
            }
        }
    }
}

/// The volume on a phone, which has no room for it in the header, and what other apps do while the radio is busy
/// (ADR-0043, ADR-0044).
struct AudioSettings: View {
    @Bindable var model: RadioViewModel
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        Form {
            Section {
                #if os(iOS)
                    if sizeClass == .compact {
                        VolumeSlider(model: model)
                    }
                #endif
                if model.canChooseOtherAudio {
                    otherAudio
                }
            }
        }
    }

    @ViewBuilder private var otherAudio: some View {
        Picker("Other audio", selection: $model.otherAudioMode) {
            ForEach(model.otherAudioModes, id: \.self) { Text($0.label) }
        }
        .explained(ControlHelp.otherAudio)
        if model.otherAudioMode.changesOtherAudio {
            Picker("Resume after", selection: $model.otherAudioResumeSeconds) {
                ForEach(RadioViewModel.otherAudioResumeOptions, id: \.self) { Text("\($0) s") }
            }
        }
        if let warning = model.otherAudioMode.warning {
            Label(warning, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
        if let hint = model.otherAudioHint {
            Text(hint).font(.footnote).foregroundStyle(.secondary)
        }
        if model.otherAudioMode == .muteAll {
            Text(ControlHelp.muteAll).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// The position beacon and the APRS network.
struct APRSSettings: View {
    @Bindable var model: RadioViewModel

    var body: some View {
        Form {
            Section("Position beacon") {
                Toggle("Position beacon", isOn: $model.isBeaconEnabled)
                    .disabled(!model.canBeacon || !model.canSendOnAir)
                    .explained(ControlHelp.beacon)
                if model.isDenied(.location) {
                    PermissionNotice(permission: .location)
                }
                Picker("Symbol", selection: $model.beaconSymbol) {
                    ForEach(APRSSymbol.allCases, id: \.self) { symbol in
                        if let image = symbol.systemImage {
                            Label(symbol.name, systemImage: image)
                        } else {
                            Text(symbol.name)
                        }
                    }
                }
                .explained(ControlHelp.symbol)
                Picker("Position accuracy", selection: $model.beaconAccuracy) {
                    ForEach(BeaconAccuracy.allCases, id: \.self) { Text($0.label) }
                }
                .explained(ControlHelp.accuracy)
                Picker("Beacon on", selection: $model.beaconFrequency) {
                    Text("Current frequency").tag(Float?.none)
                    ForEach(AppSettings.beaconFrequencyOptions, id: \.self) { frequency in
                        Text(HamFrequency.format(frequency) + " MHz").tag(Float?.some(frequency))
                    }
                }
                .explained(ControlHelp.beaconFrequency)
            }
            Section("Network") {
                Toggle("Digipeat", isOn: $model.isDigipeatingEnabled)
                    .disabled(!model.canSendOnAir)
                    .explained(ControlHelp.digipeat)
                Toggle("iGate (report RF packets online)", isOn: $model.isIGateEnabled)
                    .disabled(!model.canUseInternetWithCallsign)
                    .explained(ControlHelp.iGate)
                Toggle("Show nearby APRS-IS packets", isOn: $model.isInternetFeedEnabled)
                    .disabled(!model.canUseInternetWithCallsign)
                    .explained(ControlHelp.internetFeed)
                if model.isIGateEnabled || model.isInternetFeedEnabled {
                    Label(
                        model.isInternetConnected ? "APRS-IS connected" : "Connecting to APRS-IS…",
                        systemImage: model.isInternetConnected ? "network" : "network.slash"
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The simulated radio: its properties take effect at the next connection; the rest acts on the running one.
struct SimulatorSettings: View {
    @Bindable var model: RadioViewModel

    var body: some View {
        Form {
            Section {
                Picker("Band", selection: $model.simulatorSettings.band) {
                    ForEach(SimulatedBand.allCases, id: \.self) { Text($0.label) }
                }
                Picker("Firmware", selection: $model.simulatorSettings.hasCurrentFirmware) {
                    Text("Current").tag(true)
                    Text("Too old").tag(false)
                }
                Toggle("FreeDV modem", isOn: $model.simulatorSettings.hasFreeDVModem)
                Toggle("Power switch", isOn: $model.simulatorSettings.hasPowerSwitch)
                Toggle("SA818 module found", isOn: $model.simulatorSettings.hasRadioModule)
                Toggle("Radio answers", isOn: $model.simulatorSettings.answers)
            } header: {
                Text("Simulated radio")
            } footer: {
                Text(
                    model.canConnect
                        ? "These take effect at the next connection." : "Disconnect to change these settings."
                )
            }
            .disabled(!model.canConnect)
            if model.canSimulateSignal {
                Section("Simulator actions") {
                    Picker("Received signal", selection: $model.simulatedSignal) {
                        Text("None").tag(SimulatedSignal?.none)
                        ForEach(SimulatedSignal.allCases, id: \.self) { Text($0.label).tag(SimulatedSignal?.some($0)) }
                    }
                    .disabled(model.isSignalRampRunning)
                    Button(model.isSignalRampRunning ? "Stop signal ramp" : "Ramp signal up and down") {
                        model.toggleSignalRamp()
                    }
                    Button("Lose connection") { model.loseSimulatedConnection() }
                    ForEach(SimulatedPacket.allCases, id: \.self) { packet in
                        Button("Receive APRS \(packet.label.lowercased())") { model.simulatePacket(packet) }
                    }
                }
            }
        }
    }
}

/// `SettingsActivity`'s TX frequency limits, in whole MHz.
struct AdvancedSettings: View {
    @Bindable var model: RadioViewModel

    var body: some View {
        Form {
            Section("Frequency limits") {
                limitPicker("2 m from", $model.txLimits.min2m, TXLimits.min2mOptions)
                limitPicker("2 m to", $model.txLimits.max2m, TXLimits.max2mOptions)
                limitPicker("70 cm from", $model.txLimits.min70cm, TXLimits.min70cmOptions)
                limitPicker("70 cm to", $model.txLimits.max70cm, TXLimits.max70cmOptions)
                Text(ControlHelp.frequencyLimits).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func limitPicker(_ title: String, _ value: Binding<Float>, _ options: [Float]) -> some View {
        Picker(title, selection: value) {
            ForEach(options, id: \.self) { Text("\(Int($0)) MHz").tag($0) }
        }
    }
}

extension APRSSymbol {
    /// A system symbol, if one fits; milestone 4.3 finds a solution for the others.
    fileprivate var systemImage: String? {
        switch self {
        case .phone: "iphone"
        case .person: "figure.stand"
        case .house: "house"
        case .bicycle: "bicycle"
        case .car: "car"
        case .jeep: "suv.side"
        case .truck: "truck.box"
        case .motorcycle: "motorcycle"
        case .eighteenWheeler: "box.truck"
        case .smallAircraft: "airplane"
        case .sailboat: "sailboat"
        case .van, .rv, .glider, .helicopter, .motorboat: nil
        }
    }
}
