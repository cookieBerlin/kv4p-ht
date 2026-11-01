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
                .disabled(!model.canConnect)
                HStack {
                    Text(model.statusText)
                        .foregroundStyle(model.message == nil ? Color.secondary : Color.red)
                    Spacer()
                    if model.canConnect {
                        Button("Connect") { Task { await model.connect() } }
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Disconnect") { Task { await model.disconnect() } }
                    }
                }
                if let firmware = model.firmwareText {
                    Text(firmware).foregroundStyle(.secondary)
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
