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
                Gauge(value: Double(model.sMeter), in: 0...13) {
                    Text("S-meter")
                } currentValueLabel: {
                    Text(model.sMeterText)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420)
        .onAppear { model.refreshConnections() }
    }
}
