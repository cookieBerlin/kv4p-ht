import KV4PPersistence
import KV4PProtocol
import KV4PRadio
import SwiftUI

/// The memory list: group filter, tune on click, scan, add, edit and delete.
struct MemoriesView: View {
    @Bindable var model: RadioViewModel
    @State private var editing: ChannelMemory?

    var body: some View {
        VStack(spacing: 0) {
            controls
            list
        }
        .sheet(item: $editing) { memory in
            NavigationStack {
                MemoryEditor(memory: memory) { saved in
                    Task { await model.save(saved) }
                }
            }
        }
    }

    /// The group shown and what acts on the memories, above the list.
    private var controls: some View {
        HStack {
            Text("Group")
            Picker("Group", selection: $model.selectedGroup) {
                Text("All").tag(String?.none)
                ForEach(model.groups, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .labelsHidden()
            .fixedSize()
            Spacer()
            Button(model.isScanning ? "Stop scan" : "Scan") {
                Task { await model.toggleScan() }
            }
            .buttonStyle(.bordered)
            .disabled(!model.isReady || model.visibleMemories.isEmpty)
            .help(ControlHelp.scan)
            Button("Add memory", systemImage: "plus") {
                editing = ChannelMemory(
                    name: "",
                    frequency: Float(model.frequencyText) ?? 146.52,
                    group: model.selectedGroup ?? ""
                )
            }
            .labelStyle(.iconOnly)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var list: some View {
        List(selection: Binding(get: { model.activeMemoryId }, set: { id in tune(id) })) {
            ForEach(model.visibleMemories) { memory in
                HStack {
                    VStack(alignment: .leading) {
                        Text(memory.name)
                        Text(HamFrequency.format(memory.frequency) + " MHz").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    #if os(iOS)
                        // iOS lists select only in edit mode: a tap tunes, a checkmark marks the active memory.
                        if memory.id == model.activeMemoryId {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    #endif
                    Menu {
                        actions(memory)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title2)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .menuIndicator(.hidden)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Actions for \(memory.name)")
                }
                .tag(memory.id)
                #if os(iOS)
                    .contentShape(.rect)
                    .onTapGesture { tune(memory.id) }
                #endif
                .contextMenu { actions(memory) }
                .swipeActions {
                    Button("Delete", role: .destructive) { Task { await model.delete(memory) } }
                    Button("Edit…") { editing = memory }
                }
            }
        }
    }

    @ViewBuilder private func actions(_ memory: ChannelMemory) -> some View {
        Button("Edit…") { editing = memory }
        Button("Delete", role: .destructive) { Task { await model.delete(memory) } }
    }

    private func tune(_ id: Int32?) {
        guard let memory = model.memories.first(where: { $0.id == id }) else { return }
        Task { await model.tune(to: memory) }
    }
}

/// Add or edit a memory.
private struct MemoryEditor: View {
    @State var memory: ChannelMemory
    let save: (ChannelMemory) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            TextField("Name", text: $memory.name)
            TextField("Frequency (MHz)", value: $memory.frequency, format: .number.precision(.fractionLength(4)))
            Picker("Offset", selection: $memory.offset) {
                Text("None").tag(MemoryOffset.none)
                Text("Down").tag(MemoryOffset.down)
                Text("Up").tag(MemoryOffset.up)
            }
            TextField("Offset (kHz)", value: $memory.offsetKHz, format: .number)
                .disabled(memory.offset == .none)
            Picker("TX tone (CTCSS)", selection: $memory.txTone) {
                ForEach(CTCSS.labels, id: \.self) { Text($0) }
            }
            Picker("RX tone (CTCSS)", selection: $memory.rxTone) {
                ForEach(CTCSS.labels, id: \.self) { Text($0) }
            }
            TextField("Group", text: $memory.group)
            Toggle("Skip during scan", isOn: $memory.skipDuringScan)
        }
        .formStyle(.grouped)
        #if os(macOS)
            .frame(minWidth: 360)
        #else
            .navigationTitle(memory.name.isEmpty ? "New memory" : memory.name)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save(memory)
                    dismiss()
                }
                .disabled(memory.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
