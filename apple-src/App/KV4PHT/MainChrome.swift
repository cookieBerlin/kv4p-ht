import KV4PAudio
import KV4PRadio
import OSLog
import SwiftUI

extension View {
    /// With room for it, the parts around the memories and APRS: the header, the PTT bar and the settings button.
    func mainChrome(_ model: RadioViewModel, title: String) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                RadioHeader(model: model)
                Divider()
            }
            .background(.bar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PTTBar(model: model).background(.bar)
        }
        .navigationTitle(title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(macOS)
                SettingsLink { Label("Settings", systemImage: "gearshape") }
            #else
                NavigationLink {
                    SettingsView(model: model)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            #endif
        }
    }
}

/// The connection, the frequency and the S-meter, as at the top of the Android app.
struct RadioHeader: View {
    @Bindable var model: RadioViewModel
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var isCompact: Bool {
        #if os(iOS)
            sizeClass == .compact
        #else
            false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            connection
            if model.isWebFlasherNeeded {
                WebFlasherNotice()
            } else if model.isFirmwareOutdated || model.firmwareUpdate != .idle {
                FirmwareUpdateRow(model: model)
            }
            if let name = model.activeMemoryName {
                Text(name).font(.headline).lineLimit(1)
            }
            frequency
            HStack {
                SMeterBars(value: model.sMeter, squelch: model.isReady ? model.squelch : nil)
                Text(model.sMeterText)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 58, alignment: .trailing)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("S-meter")
            .accessibilityValue(model.isReady ? "\(model.sMeterText), squelch \(model.squelch)" : model.sMeterText)
            .help(ControlHelp.meter)
            if !isCompact {
                VolumeSlider(model: model)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// A phone has no room for the picker next to the status, so the status opens the list of radios.
    private var connection: some View {
        HStack {
            if isCompact {
                if model.canConnect, !model.firmwareUpdate.isRunning {
                    Menu {
                        radioPicker
                    } label: {
                        Label {
                            status
                        } icon: {
                            Image(systemName: "chevron.up.chevron.down")
                        }
                    }
                } else {
                    status
                }
            } else {
                radioPicker.fixedSize()
                status
            }
            Spacer()
            if model.canConnect {
                Button("Connect") { Task { await model.connect() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.firmwareUpdate.isRunning)
            } else {
                Button("Disconnect") { Task { await model.disconnect() } }
            }
        }
    }

    private var radioPicker: some View {
        Picker("Radio", selection: $model.selectedConnection) {
            ForEach(model.connections) { Text($0.label).tag($0) }
        }
        .disabled(!model.canConnect || model.firmwareUpdate.isRunning)
    }

    private var status: some View {
        Text(model.statusText)
            .lineLimit(2)
            .foregroundStyle(model.message == nil ? Color.secondary : Color.red)
    }

    private var frequency: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TextField("Frequency", text: $model.frequencyText)
                .onSubmit { Task { await model.applyFrequency() } }
                #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    .submitLabel(.done)
                #endif
                .textFieldStyle(.plain)
                .font(.system(size: isCompact ? 34 : 40, weight: .medium, design: .monospaced))
                .fixedSize()
                .disabled(!model.isReady)
            Text("MHz").foregroundStyle(.secondary)
            if let band = model.bandText {
                Text(band).font(.caption.bold()).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: model.isReceiving ? "speaker.wave.2.fill" : "speaker.slash")
                .foregroundStyle(model.isReceiving ? Color.green : Color.secondary)
                .accessibilityLabel(model.isReceiving ? "Squelch open" : "Squelch closed")
                .help(ControlHelp.meter)
        }
    }
}

/// The S-meter as a row of bars, as in the Android app. A line over the full height shows the squelch level: level n
/// stands at the end of bar n, as a signal of S n lights n bars.
private struct SMeterBars: View {
    private static let spacing: CGFloat = 2
    private static let markWidth: CGFloat = 2

    let value: Int
    let squelch: Int?

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(0..<RadioViewModel.sMeterBarCount, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(bar < value ? Color.green : Color.secondary.opacity(0.25))
                    .frame(height: 16)
            }
        }
        .overlay {
            GeometryReader { geometry in
                if let squelch {
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: Self.markWidth)
                        .offset(x: markOffset(squelch, width: geometry.size.width))
                }
            }
        }
    }

    private func markOffset(_ squelch: Int, width: CGFloat) -> CGFloat {
        let barEnd = (width + Self.spacing) * CGFloat(squelch) / CGFloat(RadioViewModel.sMeterBarCount) - Self.spacing
        return max(0, barEnd - Self.markWidth)
    }
}

struct VolumeSlider: View {
    @Bindable var model: RadioViewModel

    var body: some View {
        Slider(value: $model.volume, in: 0...1) {
            Text("Volume")
        } minimumValueLabel: {
            Image(systemName: "speaker.fill")
        } maximumValueLabel: {
            Image(systemName: "speaker.wave.3.fill")
        }
    }
}

/// PTT stays in reach below the memories and APRS.
struct PTTBar: View {
    let model: RadioViewModel

    var body: some View {
        VStack(spacing: 6) {
            if model.isReady, !model.canTransmit {
                Text("Can't transmit outside the ham band.").font(.footnote).foregroundStyle(.secondary)
            }
            PTTButton(model: model).disabled(!model.isReady)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// Press and hold to transmit; with sticky PTT, each press toggles.
private struct PTTButton: View {
    private static let log = Logger(subsystem: "kv4p-ht", category: "ptt")

    let model: RadioViewModel
    @Environment(\.isEnabled) private var isEnabled
    @State private var isPressed = false
    @State private var pressedAt = ContinuousClock.now

    var body: some View {
        Label(model.isOnAir ? "On air" : "Push to talk", systemImage: model.isTransmitting ? "mic.fill" : "mic")
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(model.isTransmitting ? Color.white : isEnabled ? Color.primary : Color.secondary)
            .background(
                model.isTransmitting ? Color.red : Color.secondary.opacity(isEnabled ? 0.2 : 0.08),
                in: .rect(cornerRadius: 8)
            )
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        pressedAt = .now
                        Self.log.info("press recognised")
                        Task { await model.pressPTT() }
                    }
                    .onEnded { _ in
                        isPressed = false
                        Task { await model.releasePTT() }
                    }
            )
            .onChange(of: model.isTransmitting) {
                if model.isTransmitting {
                    Self.log.info("on after \(String(describing: ContinuousClock.now - pressedAt), privacy: .public)")
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: isPressed) { _, pressed in pressed }
            .sensoryFeedback(.impact, trigger: model.isTransmitting)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { Task { await model.isTransmitting ? model.releasePTT() : model.pressPTT() } }
    }
}
