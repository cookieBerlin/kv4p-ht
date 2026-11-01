import KV4PAudio
import KV4PProtocol
import KV4PRadio
import SwiftUI

/// The radio screen; it only binds to `RadioViewModel`.
struct RadioView: View {
    @Bindable var model: RadioViewModel
    #if os(iOS)
        @State private var isShowingAbout = false
    #endif

    var body: some View {
        Form {
            Section("Connection") {
                Picker("Radio", selection: $model.selectedConnection) {
                    ForEach(model.connections) { Text($0.label).tag($0) }
                }
                .disabled(!model.canConnect || model.firmwareUpdate.isRunning)
                HStack {
                    Text(model.statusText)
                        .foregroundStyle(model.message == nil ? Color.secondary : Color.red)
                    Spacer()
                    if model.canConnect {
                        Button("Connect") { Task { await model.connect() } }
                            .keyboardShortcut(.defaultAction)
                            .disabled(model.firmwareUpdate.isRunning)
                    } else {
                        Button("Disconnect") { Task { await model.disconnect() } }
                    }
                }
                if let firmware = model.firmwareText {
                    Text(firmware).foregroundStyle(.secondary)
                }
                if model.canUpdateFirmware || model.firmwareUpdate != .idle {
                    FirmwareUpdateRow(model: model)
                }
                if model.isWebFlasherNeeded {
                    WebFlasherNotice()
                }
            }

            Section("Channel") {
                TextField("Frequency (MHz)", text: $model.frequencyText)
                    .onSubmit { Task { await model.applyFrequency() } }
                    #if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
                        .submitLabel(.done)
                    #endif
                Picker("Bandwidth", selection: $model.isWideBandwidth) {
                    Text("12.5 kHz").tag(false)
                    Text("25 kHz").tag(true)
                }
                Stepper("Squelch \(model.squelch)", value: $model.squelch, in: 0...8)
                Picker("TX tone (CTCSS)", selection: $model.txTone) {
                    ForEach(CTCSS.labels, id: \.self) { Text($0) }
                }
                Picker("RX tone (CTCSS)", selection: $model.rxTone) {
                    ForEach(CTCSS.labels, id: \.self) { Text($0) }
                }
                Toggle("High power", isOn: $model.isHighPower)
                Picker("Voice mode", selection: $model.isFreeDV) {
                    Text("Analog").tag(false)
                    Text("FreeDV 2400B").tag(true)
                }
                .disabled(!model.supportsFreeDV)
                if model.isReady, !model.supportsFreeDV {
                    Text("The firmware of this radio has no FreeDV 2400B modem.").foregroundStyle(.secondary)
                }
            }
            .disabled(!model.isReady)

            Section("Audio filters") {
                Toggle("Pre-emphasis", isOn: $model.filters.preEmphasis)
                Toggle("High-pass", isOn: $model.filters.highPass)
                Toggle("Low-pass", isOn: $model.filters.lowPass)
            }
            .disabled(!model.isReady)

            Section("Signal") {
                LabeledContent("Squelch") {
                    Label(
                        model.isReceiving ? "Open" : "Closed",
                        systemImage: model.isReceiving ? "speaker.wave.2.fill" : "speaker.slash"
                    )
                    .foregroundStyle(model.isReceiving ? Color.green : Color.secondary)
                }
                Gauge(value: Double(model.sMeter), in: 0...13) {
                    Text("S-meter")
                } currentValueLabel: {
                    Text(model.sMeterText)
                }
                if model.canSimulateSignal {
                    Toggle("Simulate a received signal", isOn: $model.isSignalSimulated)
                }
            }

            Section("Transmit") {
                #if os(macOS)
                    PTTButton(model: model)
                #endif
                Toggle("Sticky PTT", isOn: $model.isStickyPTT)
                Picker("Mic gain boost", selection: $model.micGain) {
                    ForEach(MicGain.allCases, id: \.self) { Text($0.label) }
                }
                if model.isReady, !model.canTransmit {
                    Text("Can't transmit outside the ham band.").foregroundStyle(.secondary)
                }
            }
            .disabled(!model.isReady)

            Section("TX limits") {
                limitPicker("2 m from", $model.txLimits.min2m, TXLimits.min2mOptions)
                limitPicker("2 m to", $model.txLimits.max2m, TXLimits.max2mOptions)
                limitPicker("70 cm from", $model.txLimits.min70cm, TXLimits.min70cmOptions)
                limitPicker("70 cm to", $model.txLimits.max70cm, TXLimits.max70cmOptions)
            }

            Section("Audio") {
                Slider(value: $model.volume, in: 0...1) {
                    Text("Volume")
                } minimumValueLabel: {
                    Image(systemName: "speaker.fill")
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3.fill")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshConnections() }
        #if os(macOS)
            .frame(minWidth: 420)
        #else
            .navigationTitle("Radio")
            .pttBar(model)
            .toolbar {
                Button("About kv4p HT", systemImage: "info.circle") { isShowingAbout = true }
            }
            .sheet(isPresented: $isShowingAbout) {
                NavigationStack {
                    AboutView().toolbar { Button("Done") { isShowingAbout = false } }
                }
            }
        #endif
    }

    /// `SettingsActivity`'s TX frequency limits, in whole MHz.
    private func limitPicker(_ title: String, _ value: Binding<Float>, _ options: [Float]) -> some View {
        Picker(title, selection: value) {
            ForEach(options, id: \.self) { Text("\(Int($0)) MHz").tag($0) }
        }
    }
}

/// `FirmwareActivity`: flashes the packaged firmware after a confirmation, with progress and the result.
private struct FirmwareUpdateRow: View {
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

#if os(iOS)
    extension View {
        /// iOS: the frequency, the S-meter and a large PTT button stay at the bottom, within reach of the thumb.
        func pttBar(_ model: RadioViewModel) -> some View {
            safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    HStack {
                        Text(model.isReady ? "\(model.frequencyText) MHz" : model.statusText)
                        Spacer()
                        Text(model.sMeterText)
                    }
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    PTTButton(model: model, height: 64)
                        .disabled(!model.isReady)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
    }
#endif

/// iOS: the app cannot reach the radio's USB port, so it points to the web flasher and the manual.
private struct WebFlasherNotice: View {
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

/// Press and hold to transmit; with sticky PTT, each press toggles.
private struct PTTButton: View {
    let model: RadioViewModel
    var height: CGFloat = 44
    @State private var isPressed = false

    var body: some View {
        Label(model.isOnAir ? "On air" : "Push to talk", systemImage: model.isTransmitting ? "mic.fill" : "mic")
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(model.isTransmitting ? Color.white : Color.primary)
            .background(model.isTransmitting ? Color.red : Color.secondary.opacity(0.2), in: .rect(cornerRadius: 8))
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        Task { await model.pressPTT() }
                    }
                    .onEnded { _ in
                        isPressed = false
                        Task { await model.releasePTT() }
                    }
            )
            .sensoryFeedback(.impact, trigger: model.isTransmitting)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { Task { await model.isTransmitting ? model.releasePTT() : model.pressPTT() } }
    }
}
