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
                Section { NavigationLink("About kv4p HT") { AboutView() } }
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
            case .advanced: AdvancedSettings(model: model)
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
            if model.canConfigureSimulator {
                Text("This gives the simulated radio the current firmware. No real radio is changed.")
            } else {
                Text(
                    "This replaces the firmware on your kv4p HT with the version the app ships. Keep the USB cable "
                        + "connected until the update is finished."
                )
            }
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
