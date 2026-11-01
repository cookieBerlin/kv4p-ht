import KV4PPersistence
import KV4PProtocol
import KV4PRadio
import SwiftUI
import UniformTypeIdentifiers

/// The memory list: group filter, tune on click, scan, add, edit, delete and RepeaterBook import.
struct MemoriesView: View {
    @Bindable var model: RadioViewModel
    @State private var editing: ChannelMemory?
    @State private var isImporting = false
    @State private var importedCSV: String?
    @State private var importGroup = ""

    var body: some View {
        List(selection: Binding(get: { model.activeMemoryId }, set: { id in tune(id) })) {
            Picker("Group", selection: $model.selectedGroup) {
                Text("All").tag(String?.none)
                ForEach(model.groups, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            ForEach(model.visibleMemories) { memory in
                HStack {
                    VStack(alignment: .leading) {
                        Text(memory.name)
                        Text(HamFrequency.format(memory.frequency) + " MHz").font(.caption).foregroundStyle(.secondary)
                    }
                    #if os(iOS)
                        // iOS lists select only in edit mode: a tap tunes, a checkmark marks the active memory.
                        Spacer()
                        if memory.id == model.activeMemoryId {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    #endif
                }
                .tag(memory.id)
                #if os(iOS)
                    .contentShape(.rect)
                    .onTapGesture { tune(memory.id) }
                #endif
                .contextMenu {
                    Button("Edit…") { editing = memory }
                    Button("Delete", role: .destructive) { Task { await model.delete(memory) } }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { Task { await model.delete(memory) } }
                    Button("Edit…") { editing = memory }
                }
            }
        }
        .navigationTitle("Memories")
        .toolbar {
            ToolbarItemGroup {
                Button(
                    model.isScanning ? "Stop scan" : "Scan",
                    systemImage: model.isScanning ? "stop.fill" : "dot.radiowaves.left.and.right"
                ) {
                    Task { await model.toggleScan() }
                }
                .disabled(!model.isReady || model.visibleMemories.isEmpty)
                Button("Add memory", systemImage: "plus") {
                    editing = ChannelMemory(
                        name: "",
                        frequency: Float(model.frequencyText) ?? 146.52,
                        group: model.selectedGroup ?? ""
                    )
                }
                Button("Import RepeaterBook CSV…", systemImage: "square.and.arrow.down") { isImporting = true }
            }
        }
        .sheet(item: $editing) { memory in
            NavigationStack {
                MemoryEditor(memory: memory) { saved in
                    Task { await model.save(saved) }
                }
            }
        }
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
        .task { await model.loadMemories() }
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
