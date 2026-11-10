import KV4PPersistence
import KV4PProtocol
import KV4PRadio
import SwiftUI

/// The memory list: group filter, tune on click, scan, add, edit and delete.
struct MemoriesView: View {
    @Bindable var model: RadioViewModel
    @State private var editing: ChannelMemory?
    @State private var deleting: [ChannelMemory]?
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        VStack(spacing: 0) {
            controls
            list
        }
        .sheet(item: $editing) { memory in
            NavigationStack {
                MemoryForm(model: model, memory: memory) { saved in
                    Task { await model.save(saved) }
                }
            }
        }
        .confirmsDeletion(of: $deleting, model: model)
    }

    /// The group shown and what acts on the memories, above the list; in two rows with the accessibility text sizes.
    private var controls: some View {
        Group {
            if textSize.isAccessibilitySize {
                VStack(alignment: .leading) {
                    groupChoice
                    HStack {
                        Spacer()
                        actions
                    }
                }
            } else {
                HStack {
                    groupChoice
                    Spacer()
                    actions
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var groupChoice: some View {
        HStack {
            Text("Group")
            Picker("Group", selection: $model.selectedGroup) {
                Text("All").tag(String?.none)
                ForEach(model.groups, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    @ViewBuilder private var actions: some View {
        Button(model.isScanning ? "Stop scan" : "Scan") {
            Task { await model.toggleScan() }
        }
        .capsuleButton(isActive: model.isScanning)
        .disabled(!model.isReady || model.visibleMemories.isEmpty)
        .help(ControlHelp.scan)
        Button("Add memory", systemImage: "plus") {
            editing = model.draftMemory(group: model.selectedGroup ?? "")
        }
        .labelStyle(.iconOnly)
        .capsuleButton()
    }

    private var list: some View {
        List(selection: Binding(get: { model.activeMemoryId }, set: { id in tune(id) })) {
            ForEach(model.visibleMemories) { memory in
                HStack {
                    HStack {
                        MemoryKindSymbol(kind: memory.kind)
                        VStack(alignment: .leading) {
                            Text(memory.name)
                            Text(model.shown(memory.frequency) + " MHz").font(.caption)
                                .foregroundStyle(Color.strongSecondary)
                            if !memory.comment.isEmpty, !textSize.isAccessibilitySize {
                                Text(memory.comment).font(.caption).lineLimit(1)
                                    .foregroundStyle(Color.strongSecondary)
                            }
                        }
                    }
                    // One element to tap and to read, with the kind and the active one marked.
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(memory.id == model.activeMemoryId ? .isSelected : [])
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
                    Button("Delete", role: .destructive) { deleting = [memory] }
                    Button("Edit…") { editing = memory }
                }
            }
        }
        .macName("Memories")
    }

    @ViewBuilder private func actions(_ memory: ChannelMemory) -> some View {
        Button("Edit…") { editing = memory }
        Button("Delete", role: .destructive) { deleting = [memory] }
    }

    private func tune(_ id: Int32?) {
        guard let memory = model.memories.first(where: { $0.id == id }) else { return }
        Task { await model.tune(to: memory) }
    }
}
