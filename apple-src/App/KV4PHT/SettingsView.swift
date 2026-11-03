import KV4PAPRS
import KV4PAudio
import KV4PProtocol
import KV4PRadio
import SwiftUI
import UniformTypeIdentifiers

/// All settings on one screen, as in the Android app; the Mac shows them in its settings window.
struct SettingsView: View {
    @Bindable var model: RadioViewModel
    /// The callsign as typed; the model keeps it normalised in the settings.
    @State private var callsign = ""
    @State private var areLimitsShown = false
    @State private var isImporting = false
    @State private var importedCSV: String?
    @State private var importGroup = ""
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        Form {
            Section("Station") {
                LabeledContent("Your callsign") {
                    TextField("Your callsign", text: $callsign, prompt: Text("N0CALL"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        #endif
                        .onChange(of: callsign) { model.callsign = callsign }
                }
            }

            radio

            radioSettings

            #if os(iOS)
                // A phone has no room for the volume in the header.
                if sizeClass == .compact {
                    Section("Audio") { VolumeSlider(model: model) }
                }
            #endif

            aprs

            Section("Memories") {
                Button("Import RepeaterBook CSV…", systemImage: "square.and.arrow.down") { isImporting = true }
                    .explained(ControlHelp.importCSV)
            }

            Section("Advanced") {
                DisclosureGroup(isExpanded: $areLimitsShown) {
                    limitPicker("2 m from", $model.txLimits.min2m, TXLimits.min2mOptions)
                    limitPicker("2 m to", $model.txLimits.max2m, TXLimits.max2mOptions)
                    limitPicker("70 cm from", $model.txLimits.min70cm, TXLimits.min70cmOptions)
                    limitPicker("70 cm to", $model.txLimits.max70cm, TXLimits.max70cmOptions)
                    Text(ControlHelp.frequencyLimits).font(.footnote).foregroundStyle(.secondary)
                } label: {
                    Text("Frequency limits")
                        #if os(macOS)
                            // The Mac opens the group only on its small triangle, unless the row reacts too.
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                            .onTapGesture { withAnimation { areLimitsShown.toggle() } }
                        #endif
                }
            }

            #if os(iOS)
                Section { NavigationLink("About kv4p HT") { AboutView() } }
            #endif
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isPage { NoticeBanner(model: model) }
        }
        .onAppear { callsign = model.callsign }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            importedCSV = try? String(contentsOf: url, encoding: .utf8)
            importGroup = url.deletingPathExtension().lastPathComponent
        }
        .alert(
            "Save repeaters as group",
            isPresented: Binding(get: { importedCSV != nil }, set: { if !$0 { importedCSV = nil } })
        ) {
            TextField("Group", text: $importGroup)
            Button("Import") {
                let csv = importedCSV ?? ""
                Task { await model.importRepeaterBook(csv, group: importGroup) }
            }
            Button("Cancel", role: .cancel) {}
        }
        #if os(macOS)
            .frame(minWidth: 480, minHeight: 560)
        #else
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// On a phone, the screen around the settings page shows the notices.
    private var isPage: Bool {
        #if os(iOS)
            sizeClass == .compact
        #else
            false
        #endif
    }

    /// What needs a radio; without one, the sections stay and say so.
    @ViewBuilder private var radioSettings: some View {
        radioSection("Channel") {
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
            if !model.supportsFreeDV {
                Text("The firmware of this radio has no FreeDV 2400B modem.").foregroundStyle(.secondary)
            }
        }
        radioSection("Audio filters") {
            Toggle("Pre-emphasis", isOn: $model.filters.preEmphasis)
                .explained(ControlHelp.preEmphasis)
            Toggle("High-pass", isOn: $model.filters.highPass)
                .explained(ControlHelp.highPass)
            Toggle("Low-pass", isOn: $model.filters.lowPass)
                .explained(ControlHelp.lowPass)
        }
        radioSection("Transmit") {
            Toggle("Sticky PTT", isOn: $model.isStickyPTT)
                .explained(ControlHelp.stickyPTT)
            Picker("Mic gain boost", selection: $model.micGain) {
                ForEach(MicGain.allCases, id: \.self) { Text($0.label) }
            }
            .explained(ControlHelp.micGain)
        }
    }

    private func radioSection(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        Section(title) {
            if model.isReady {
                rows()
            } else {
                Text("Not available while no radio is connected.").foregroundStyle(.secondary)
            }
        }
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
