import KV4PAPRS
import KV4PAudio
import KV4PProtocol
import KV4PRadio
import SwiftUI

/// All settings on one screen, as in the Android app; the Mac shows them in its settings window.
struct SettingsView: View {
    @Bindable var model: RadioViewModel
    /// The callsign as typed; the model keeps it normalised in the settings.
    @State private var callsign = ""
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        Form {
            Section("Station") {
                TextField("Your callsign", text: $callsign)
                    #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    #endif
                    .onChange(of: callsign) { model.callsign = callsign }
            }

            radio

            Section("Channel") {
                Picker("Bandwidth", selection: $model.isWideBandwidth) {
                    Text("12.5 kHz").tag(false)
                    Text("25 kHz").tag(true)
                }
                .explained(ControlHelp.bandwidth)
                Stepper("Squelch \(model.squelch)", value: $model.squelch, in: 0...8)
                    .explained(ControlHelp.squelch)
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
                if model.isReady, !model.supportsFreeDV {
                    Text("The firmware of this radio has no FreeDV 2400B modem.").foregroundStyle(.secondary)
                }
            }
            .disabled(!model.isReady)

            Section("Audio filters") {
                Toggle("Pre-emphasis", isOn: $model.filters.preEmphasis)
                    .explained(ControlHelp.preEmphasis)
                Toggle("High-pass", isOn: $model.filters.highPass)
                    .explained(ControlHelp.highPass)
                Toggle("Low-pass", isOn: $model.filters.lowPass)
                    .explained(ControlHelp.lowPass)
            }
            .disabled(!model.isReady)

            Section("Transmit") {
                Toggle("Sticky PTT", isOn: $model.isStickyPTT)
                    .explained(ControlHelp.stickyPTT)
                Picker("Mic gain boost", selection: $model.micGain) {
                    ForEach(MicGain.allCases, id: \.self) { Text($0.label) }
                }
                .explained(ControlHelp.micGain)
            }
            .disabled(!model.isReady)

            Section {
                limitPicker("2 m from", $model.txLimits.min2m, TXLimits.min2mOptions)
                limitPicker("2 m to", $model.txLimits.max2m, TXLimits.max2mOptions)
                limitPicker("70 cm from", $model.txLimits.min70cm, TXLimits.min70cmOptions)
                limitPicker("70 cm to", $model.txLimits.max70cm, TXLimits.max70cmOptions)
            } header: {
                Text("TX limits")
            } footer: {
                Text(ControlHelp.txLimits)
            }

            #if os(iOS)
                // A phone has no room for the volume in the header.
                if sizeClass == .compact {
                    Section("Audio") { VolumeSlider(model: model) }
                }
            #endif

            aprs

            #if os(iOS)
                Section { NavigationLink("About kv4p HT") { AboutView() } }
            #endif
        }
        .formStyle(.grouped)
        .onAppear { callsign = model.callsign }
        #if os(macOS)
            .frame(minWidth: 480, minHeight: 560)
        #else
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder private var radio: some View {
        if model.firmwareText != nil || model.canUpdateFirmware || model.firmwareUpdate != .idle
            || model.canSimulateSignal
        {
            Section("Radio") {
                if let firmware = model.firmwareText {
                    Text(firmware).foregroundStyle(.secondary)
                }
                if model.canUpdateFirmware || model.firmwareUpdate != .idle {
                    FirmwareUpdateRow(model: model)
                }
                if model.canSimulateSignal {
                    Toggle("Simulate a received signal", isOn: $model.isSignalSimulated)
                }
            }
        }
    }

    @ViewBuilder private var aprs: some View {
        Section("APRS position beacon") {
            Toggle("Position beacon", isOn: $model.isBeaconEnabled)
                .disabled(!model.canBeacon || model.callsign.isEmpty)
                .explained(ControlHelp.beacon)
            Picker("Symbol", selection: $model.beaconSymbol) {
                ForEach(APRSSymbol.allCases, id: \.self) { Text($0.name) }
            }
            .explained(ControlHelp.symbol)
            Toggle("Approximate position", isOn: $model.isBeaconApproximate)
                .explained(ControlHelp.approximate)
            Picker("Beacon on", selection: $model.beaconFrequency) {
                Text("Current frequency").tag(Float?.none)
                ForEach(AppSettings.beaconFrequencyOptions, id: \.self) { frequency in
                    Text(HamFrequency.format(frequency) + " MHz").tag(Float?.some(frequency))
                }
            }
            .explained(ControlHelp.beaconFrequency)
        }
        Section("APRS network") {
            Toggle("Digipeat", isOn: $model.isDigipeatingEnabled)
                .disabled(model.callsign.isEmpty)
                .explained(ControlHelp.digipeat)
            Toggle("iGate (report RF packets online)", isOn: $model.isIGateEnabled)
                .disabled(!model.canUseInternet || model.callsign.isEmpty)
                .explained(ControlHelp.iGate)
            Toggle("Show nearby APRS-IS packets", isOn: $model.isInternetFeedEnabled)
                .disabled(!model.canUseInternet || model.callsign.isEmpty)
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

    /// `SettingsActivity`'s TX frequency limits, in whole MHz.
    private func limitPicker(_ title: String, _ value: Binding<Float>, _ options: [Float]) -> some View {
        Picker(title, selection: value) {
            ForEach(options, id: \.self) { Text("\(Int($0)) MHz").tag($0) }
        }
    }
}

/// `FirmwareActivity`: flashes the packaged firmware after a confirmation, with progress and the result.
struct FirmwareUpdateRow: View {
    let model: RadioViewModel
    @State private var isConfirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isFirmwareOutdated {
                Text("The radio needs a firmware update.").foregroundStyle(.orange)
            }
            switch model.firmwareUpdate {
            case .idle: EmptyView()
            case .connecting: ProgressView("Starting the bootloader…")
            case .flashing(let percent):
                ProgressView(value: Double(percent), total: 100) { Text("Updating firmware… \(percent) %") }
            case .finished: Label("Firmware updated and verified.", systemImage: "checkmark.circle")
            case .failed(let message): Text(message).foregroundStyle(.red)
            }
            Button("Update firmware…") { isConfirming = true }
                .disabled(!model.canUpdateFirmware)
        }
        .confirmationDialog("Flash firmware?", isPresented: $isConfirming) {
            Button("Flash") { Task { await model.updateFirmware() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This replaces the firmware on your kv4p HT with the version the app ships. Keep the USB cable "
                    + "connected until the update is finished."
            )
        }
    }
}

/// iOS: the app cannot reach the radio's USB port, so it points to the web flasher and the manual.
struct WebFlasherNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The radio needs a firmware update.").foregroundStyle(.orange)
            Text("Connect the radio by USB to a computer and update it with the web flasher in a desktop browser.")
                .foregroundStyle(.secondary)
            if let flasher = URL(string: FirmwareHelp.webFlasherAddress) {
                Link("Open the web flasher", destination: flasher)
            }
            if let manual = URL(string: FirmwareHelp.manualAddress) {
                Link("Firmware updates in the manual", destination: manual)
            }
        }
    }
}
