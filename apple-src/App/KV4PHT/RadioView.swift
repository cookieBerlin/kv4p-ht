import KV4PAudio
import KV4PProtocol
import KV4PRadio
import SwiftUI

/// The radio screen; it only binds to `RadioViewModel`.
struct RadioView: View {
    @Bindable var model: RadioViewModel

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
            }

            Section("Channel") {
                TextField("Frequency (MHz)", text: $model.frequencyText)
                    .onSubmit { Task { await model.applyFrequency() } }
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
                PTTButton(model: model)
                Toggle("Sticky PTT", isOn: $model.isStickyPTT)
                Picker("Mic gain boost", selection: $model.micGain) {
                    ForEach(MicGain.allCases, id: \.self) { Text($0.label) }
                }
                if model.isReady, !model.canTransmit {
                    Text("Can't transmit outside the ham band.").foregroundStyle(.secondary)
                }
            }
            .disabled(!model.isReady)

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
        .frame(minWidth: 420)
        .onAppear { model.refreshConnections() }
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

/// Press and hold to transmit; with sticky PTT, each press toggles.
private struct PTTButton: View {
    let model: RadioViewModel
    @State private var isPressed = false

    var body: some View {
        Label(model.isOnAir ? "On air" : "Push to talk", systemImage: model.isTransmitting ? "mic.fill" : "mic")
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
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
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { Task { await model.isTransmitting ? model.releasePTT() : model.pressPTT() } }
    }
}
