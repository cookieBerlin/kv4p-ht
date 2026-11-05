import KV4PFlasher
import KV4PRadio
import SwiftUI

/// The overview of the settings (ADR-0048): a sidebar in the Mac's settings window, a list of pages on iPhone and iPad.
struct SettingsView: View {
    let model: RadioViewModel
    #if os(macOS)
        @State private var selection: SettingsPage? = .station
    #else
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        #if os(macOS)
            NavigationSplitView {
                List(pages, selection: $selection) { page in
                    Label(page.title, systemImage: page.systemImage).tag(page)
                }
                .navigationSplitViewColumnWidth(180)
                .toolbar(removing: .sidebarToggle)
            } detail: {
                // The memory editor pushes its groups; another page starts with a new stack.
                NavigationStack {
                    if let selection {
                        content(of: selection)
                    }
                }
                .id(selection)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { NoticeBanner(model: model) }
            .task(id: model.isFirmwareSettingsRequested) {
                guard model.isFirmwareSettingsRequested else { return }
                selection = .radio
                model.firmwareSettingsShown()
            }
            .onChange(of: pages) {
                if let selection, !pages.contains(selection) { self.selection = .station }
            }
            .frame(minWidth: 680, minHeight: 560)
        #else
            Form {
                Section {
                    ForEach(pages) { page in
                        NavigationLink {
                            content(of: page)
                        } label: {
                            Label(page.title, systemImage: page.systemImage)
                        }
                    }
                }
                Section { NavigationLink("About kv4p HT") { AboutView(model: model) } }
            }
            .settingsPage("Settings", model: model)
        #endif
    }

    /// Without anything to set, a page is not offered.
    private var pages: [SettingsPage] {
        SettingsPage.allCases.filter { page in
            switch page {
            case .simulator: model.canConfigureSimulator
            case .audio: hasAudioSettings
            default: true
            }
        }
    }

    private var hasAudioSettings: Bool {
        #if os(iOS)
            sizeClass == .compact || model.canChooseOtherAudio
        #else
            model.canChooseOtherAudio
        #endif
    }

    @ViewBuilder private func content(of page: SettingsPage) -> some View {
        Group {
            switch page {
            case .station: StationSettings(model: model)
            case .radio: RadioSettings(model: model)
            case .transmit: TransmitSettings(model: model)
            case .audio: AudioSettings(model: model)
            case .aprs: APRSSettings(model: model)
            case .memories: ManageMemoriesView(model: model)
            case .simulator: SimulatorSettings(model: model)
            }
        }
        .settingsPage(page.title, model: model)
    }
}

extension View {
    /// What every page of the settings has in common. On a phone, the screen around the settings shows the notices;
    /// the Mac shows them below its settings window's pages.
    fileprivate func settingsPage(_ title: String, model: RadioViewModel) -> some View {
        modifier(SettingsPageStyle(title: title, model: model))
    }
}

private struct SettingsPageStyle: ViewModifier {
    let title: String
    let model: RadioViewModel
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
            content
                .formStyle(.grouped)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if sizeClass != .compact { NoticeBanner(model: model) }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        #else
            content
                .formStyle(.grouped)
                .navigationTitle(title)
        #endif
    }
}

/// `FirmwareActivity`: flashes the firmware the user chooses, with progress and the result.
struct FirmwareUpdateRow: View {
    let model: RadioViewModel
    @State private var isChoosing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.offersFirmwareSettings {
                Text("The radio needs a firmware update.").foregroundStyle(.orange)
            }
            if let hint = model.firmwareUpdateHint {
                Text(hint).font(.footnote).foregroundStyle(.secondary)
            }
            switch model.firmwareUpdate {
            case .idle: EmptyView()
            case .connecting: ProgressView("Starting the bootloader…")
            case .flashing(let percent):
                ProgressView(value: Double(percent), total: 100) { Text("Updating firmware… \(percent) %") }
            case .finished: Label("Firmware updated and verified.", systemImage: "checkmark.circle")
            case .finishedForAndroid:
                Label(
                    "Firmware updated and verified. The radio is now set up for the Android app.",
                    systemImage: "checkmark.circle"
                )
            case .failed(let message): Text(message).foregroundStyle(.red)
            }
            Button("Update firmware…") { isChoosing = true }
                .disabled(!model.canUpdateFirmware)
        }
        .sheet(isPresented: $isChoosing) {
            FirmwareChoiceSheet(model: model)
        }
    }
}

/// The firmwares the app contains; the one for this app is preselected (ADR-0049).
struct FirmwareChoiceSheet: View {
    let model: RadioViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: FirmwareChoice.ID?

    private var selection: FirmwareChoice? {
        model.firmwareChoices.first { $0.id == chosen } ?? model.firmwareChoices.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose the firmware").font(.headline)
            ForEach(model.firmwareChoices) { choice in
                Button {
                    chosen = choice.id
                } label: {
                    row(choice)
                }
                .buttonStyle(.plain)
            }
            Text(
                model.canConfigureSimulator
                    ? "This changes the simulated radio. No real radio is changed."
                    : "This replaces the firmware on your kv4p HT. Keep the USB cable connected until the update is finished."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Flash") {
                    guard let selection else { return }
                    dismiss()
                    Task { await model.updateFirmware(to: selection) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
        }
        .padding()
        .frame(minWidth: 460)
    }

    private func row(_ choice: FirmwareChoice) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: choice.id == selection?.id ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(choice.title).fontWeight(.semibold)
                Text(choice.suitability).foregroundStyle(choice.isForThisApp ? Color.secondary : Color.orange)
                ForEach(choice.details, id: \.self) {
                    Text($0).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

/// iOS: the app cannot reach the radio's USB port, so it points to a Mac, the Android nightly app and the manual.
struct FirmwareElsewhereNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The radio needs a firmware update.").foregroundStyle(.orange)
            Text(
                "Connect the radio by USB to a Mac with this app and choose the firmware for this app there. The Android nightly app can write it too."
            )
            .foregroundStyle(.secondary)
            if let manual = URL(string: FirmwareHelp.manualAddress) {
                Link("Firmware updates in the manual", destination: manual)
            }
        }
    }
}
