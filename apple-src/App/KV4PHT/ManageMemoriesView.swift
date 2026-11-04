import KV4PPersistence
import KV4PProtocol
import KV4PRadio
import SwiftUI

/// The first level of the memory editor: the groups, in their order (ADR-0042).
struct ManageMemoriesView: View {
    let model: RadioViewModel
    @State private var opened: String?
    @State private var editing: ChannelMemory?
    @State private var isNamingGroup = false
    @State private var groupName = ""
    @State private var isImporting = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(model.memoryBlocks) { block in
                    HStack {
                        DragHandle()
                        Button {
                            opened = block.name
                        } label: {
                            HStack {
                                Text(block.title)
                                Spacer()
                                Text("\(block.memories.count)").foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onMove { offsets, destination in
                    Task { await model.moveGroups(offsets, to: destination) }
                }
            } footer: {
                if model.memories.isEmpty {
                    Text("No memories yet.")
                }
            }
            Section {
                Button("New memory", systemImage: "plus") { editing = model.draftMemory(group: "") }
                Button("New group", systemImage: "folder.badge.plus") {
                    groupName = ""
                    isNamingGroup = true
                }
                Button("Import from RepeaterBook", systemImage: "square.and.arrow.down") { isImporting = true }
                    .explained(ControlHelp.importCSV)
            }
        }
        .sortableList()
        .navigationTitle("Memories")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .navigationDestination(item: $opened) { name in
            GroupMemoriesView(model: model, name: name)
        }
        .memoryFormSheet(item: $editing, model: model)
        .asksForGroupName("New group", isPresented: $isNamingGroup, name: $groupName) { name in
            editing = model.draftMemory(group: name.trimmingCharacters(in: .whitespaces))
        }
        .sheet(isPresented: $isImporting) {
            NavigationStack { RepeaterImportView(model: model) }
        }
    }
}

/// The second level of the memory editor: the memories of one group, in their order.
struct GroupMemoriesView: View {
    let model: RadioViewModel
    @State var name: String
    @State private var editing: ChannelMemory?
    @State private var deleting: [ChannelMemory]?
    @State private var isSelecting = false
    @State private var selection: Set<Int32> = []
    /// The memories on their way to a new group, while its name is asked for.
    @State private var movingToNewGroup: [ChannelMemory] = []
    @State private var isNamingNewGroup = false
    @State private var isRenaming = false
    @State private var groupName = ""
    @State private var isDeletingGroup = false
    @Environment(\.dismiss) private var dismiss

    private var memories: [ChannelMemory] { model.memories.filter { $0.group == name } }
    private var selected: [ChannelMemory] { memories.filter { selection.contains($0.id) } }

    var body: some View {
        List(selection: isSelecting ? $selection : nil) {
            ForEach(memories) { memory in
                row(memory).tag(memory.id).moveDisabled(isSelecting)
            }
            .onMove { offsets, destination in
                Task { await model.moveMemories(inGroup: name, offsets, to: destination) }
            }
        }
        .sortableList()
        .navigationTitle(name.isEmpty ? "No group" : name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New memory", systemImage: "plus") { editing = model.draftMemory(group: name) }
            }
            ToolbarItem(placement: .primaryAction) { groupMenu }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelecting { selectionBar }
        }
        .onChange(of: memories.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
        .memoryFormSheet(item: $editing, model: model)
        .confirmsDeletion(of: $deleting, model: model)
        .asksForGroupName("New group", isPresented: $isNamingNewGroup, name: $groupName) { group in
            let memories = movingToNewGroup
            let target = group.trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty else { return }
            Task { await model.move(memories, toGroup: target) }
            endSelecting()
        }
        .asksForGroupName("Rename group", isPresented: $isRenaming, name: $groupName) { newName in
            let trimmed = newName.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            let old = name
            Task {
                await model.renameGroup(old, to: trimmed)
                name = trimmed  // only now, as a view of a group without memories closes
            }
        }
        .confirmationDialog("Delete “\(name)”?", isPresented: $isDeletingGroup, titleVisibility: .visible) {
            Button("Delete the memories too", role: .destructive) {
                Task { await model.deleteGroup(name, keepingMemories: false) }
            }
            Button("Keep the memories without a group") {
                Task { await model.deleteGroup(name, keepingMemories: true) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder private func row(_ memory: ChannelMemory) -> some View {
        let content = HStack {
            VStack(alignment: .leading) {
                Text(memory.name)
                Text(HamFrequency.format(memory.frequency) + " MHz").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(.rect)

        if isSelecting {
            content
        } else {
            HStack {
                DragHandle()
                Button {
                    editing = memory
                } label: {
                    content
                }
                .buttonStyle(.plain)
                Menu {
                    Button("Edit…") { editing = memory }
                    moveMenu(for: [memory])
                    Button("Delete", role: .destructive) { deleting = [memory] }
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
        }
    }

    private var groupMenu: some View {
        Menu("More", systemImage: "ellipsis.circle") {
            Button("Select", systemImage: "checkmark.circle") {
                selection = []
                isSelecting = true
            }
            if !name.isEmpty {
                Button("Rename group", systemImage: "pencil") {
                    groupName = name
                    isRenaming = true
                }
                Button("Delete group", systemImage: "trash", role: .destructive) { isDeletingGroup = true }
            }
        }
    }

    private var selectionBar: some View {
        HStack {
            Button("Cancel") { endSelecting() }
            Spacer()
            moveMenu(for: selected).disabled(selected.isEmpty)
            Button("Delete", role: .destructive) {
                deleting = selected
                endSelecting()
            }
            .disabled(selected.isEmpty)
        }
        .padding()
        .background(.bar)
    }

    /// The groups `memories` can move to.
    private func moveMenu(for memories: [ChannelMemory]) -> some View {
        Menu("Move to group") {
            if !name.isEmpty {
                Button("No group") { move(memories, to: "") }
            }
            ForEach(model.groups.filter { $0 != name }, id: \.self) { group in
                Button(group) { move(memories, to: group) }
            }
            Button("New group…") {
                movingToNewGroup = memories
                groupName = ""
                isNamingNewGroup = true
            }
        }
    }

    private func move(_ memories: [ChannelMemory], to group: String) {
        Task { await model.move(memories, toGroup: group) }
        endSelecting()
    }

    private func endSelecting() {
        isSelecting = false
        selection = []
    }
}

extension MemoryGroup {
    var title: String { name.isEmpty ? "No group" : name }
}

/// Shows where to drag a row on the Mac; iOS draws the handle itself in an editing list.
private struct DragHandle: View {
    var body: some View {
        #if os(macOS)
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).accessibilityHidden(true)
        #endif
    }
}

extension View {
    /// A list whose rows show their drag handles at all times, on iOS through its editing mode.
    fileprivate func sortableList() -> some View {
        #if os(iOS)
            environment(\.editMode, .constant(.active))
        #else
            self
        #endif
    }

    fileprivate func memoryFormSheet(item: Binding<ChannelMemory?>, model: RadioViewModel) -> some View {
        sheet(item: item) { memory in
            NavigationStack {
                MemoryForm(model: model, memory: memory) { saved in
                    Task { await model.save(saved) }
                }
            }
        }
    }
}
