import KV4PAudio
import KV4PPersistence
import KV4PProtocol
import KV4PRadio
import SwiftUI

extension RadioViewModel {
    /// A new memory on the current frequency.
    func draftMemory(group: String) -> ChannelMemory {
        ChannelMemory(name: "", frequency: HamFrequency.parse(frequencyText) ?? 146.52, group: group)
    }
}

/// Add or edit a memory.
struct MemoryForm: View {
    let model: RadioViewModel
    let save: (ChannelMemory) -> Void
    @State private var memory: ChannelMemory
    // As typed: a field with a number format reports its value only when it loses focus, which Save does not cause.
    @State private var frequency: String
    @State private var offset: String
    @Environment(\.dismiss) private var dismiss

    init(model: RadioViewModel, memory: ChannelMemory, save: @escaping (ChannelMemory) -> Void) {
        self.model = model
        self.save = save
        _memory = State(initialValue: memory)
        _frequency = State(initialValue: model.shown(memory.frequency))
        _offset = State(initialValue: "\(memory.offsetKHz)")
    }

    /// The memory as entered; a number that cannot be read makes `memoryProblem` report it.
    private var entered: ChannelMemory {
        var entered = memory
        entered.name = memory.name.trimmingCharacters(in: .whitespaces)
        entered.group = memory.group.trimmingCharacters(in: .whitespaces)
        entered.frequency = HamFrequency.parse(frequency) ?? .nan
        entered.offsetKHz = Int(offset) ?? -1
        return entered
    }

    var body: some View {
        Form {
            Section {
                LabeledField("Name", text: $memory.name)
                GroupField(groups: model.groups, group: $memory.group)
            }
            Section {
                LabeledField("Frequency (MHz)", text: $frequency, kind: .decimal)
                Picker("Offset", selection: $memory.offset) {
                    Text("None").tag(MemoryOffset.none)
                    Text("Down").tag(MemoryOffset.down)
                    Text("Up").tag(MemoryOffset.up)
                }
                if memory.offset != .none {
                    LabeledField("Offset (kHz)", text: $offset, kind: .whole)
                }
                if entered.frequency.isFinite, let text = model.transmitText(for: entered) {
                    Text(text).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                Picker("TX tone (CTCSS)", selection: $memory.txTone) {
                    ForEach(CTCSS.labels, id: \.self) { Text($0) }
                }
                Picker("RX tone (CTCSS)", selection: $memory.rxTone) {
                    ForEach(CTCSS.labels, id: \.self) { Text($0) }
                }
                Toggle("Skip during scan", isOn: $memory.skipDuringScan)
            }
            Section {
                Picker("Access tone", selection: $memory.accessToneHz) {
                    Text("Use settings").tag(Int?.none)
                    Text("Off").tag(Int?.some(0))
                    ForEach(AccessTone.frequencies, id: \.self) { Text("\($0) Hz").tag(Int?.some($0)) }
                }
                Picker("Tone length", selection: $memory.accessToneLengthMs) {
                    Text("Use settings").tag(Int?.none)
                    ForEach(AccessTone.lengthsMs, id: \.self) { Text(AccessTone.lengthLabel($0)).tag(Int?.some($0)) }
                }
            } header: {
                Text("Repeater access tone")
            } footer: {
                if let problem = model.memoryProblem(entered) {
                    Text(problem)
                }
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
            .frame(minWidth: 400)
        #else
            .navigationTitle(memory.name.isEmpty ? "New memory" : memory.name)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save(entered)
                    dismiss()
                }
                .disabled(model.memoryProblem(entered) != nil)
            }
        }
    }
}

/// A text field that shows its label also on iOS, where a field alone shows it only while empty. A field for numbers
/// takes digits and, for a decimal number, one separator; on iPhone and iPad it brings a number keyboard with Done.
struct LabeledField: View {
    enum Kind {
        case text, decimal, whole
    }

    let label: String
    @Binding var text: String
    let kind: Kind
    @FocusState private var isFocused: Bool

    init(_ label: String, text: Binding<String>, kind: Kind = .text) {
        self.label = label
        _text = text
        self.kind = kind
    }

    var body: some View {
        LabeledContent(label) {
            TextField(label, text: filtered)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                #if os(iOS)
                    .keyboardType(kind == .decimal ? .decimalPad : kind == .whole ? .numberPad : .default)
                    .toolbar {
                        if isFocused, kind != .text {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") { isFocused = false }
                            }
                        }
                    }
                #endif
        }
    }

    private var filtered: Binding<String> {
        guard kind != .text else { return $text }
        return Binding {
            text
        } set: {
            text = NumberInput.filtered($0, allowsSeparator: kind == .decimal)
        }
    }
}

/// Chooses a group, no group or a new one; a choice instead of free text, so that a typing error adds no group.
struct GroupField: View {
    private static let newGroup = "\u{0}new"
    let groups: [String]
    @Binding var group: String
    @State private var isNew: Bool

    /// A group that does not exist yet, as from "New group" or an imported file, opens as a new one.
    init(groups: [String], group: Binding<String>) {
        self.groups = groups
        _group = group
        let current = group.wrappedValue
        _isNew = State(initialValue: !current.isEmpty && !groups.contains(current))
    }

    var body: some View {
        Picker("Group", selection: choice) {
            Text("No group").tag("")
            ForEach(groups, id: \.self) { Text($0).tag($0) }
            Text("New group…").tag(Self.newGroup)
        }
        if isNew {
            LabeledField("New group", text: $group)
        }
    }

    private var choice: Binding<String> {
        Binding(
            get: { isNew ? Self.newGroup : group },
            set: { chosen in
                isNew = chosen == Self.newGroup
                group = isNew ? "" : chosen
            }
        )
    }
}

extension View {
    /// Asks before `memories` are deleted; every way of deleting a memory goes through here.
    func confirmsDeletion(of memories: Binding<[ChannelMemory]?>, model: RadioViewModel) -> some View {
        let title =
            memories.wrappedValue.map { $0.count == 1 ? "Delete “\($0[0].name)”?" : "Delete \($0.count) memories?" }
            ?? ""
        return confirmationDialog(
            title,
            isPresented: Binding(
                get: { memories.wrappedValue != nil },
                set: { if !$0 { memories.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: memories.wrappedValue
        ) { doomed in
            Button("Delete", role: .destructive) { Task { await model.delete(doomed) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Asks for the name of a group while `isPresented`.
    func asksForGroupName(
        _ title: String,
        isPresented: Binding<Bool>,
        name: Binding<String>,
        done: @escaping (String) -> Void
    ) -> some View {
        alert(title, isPresented: isPresented) {
            TextField("Group name", text: name)
            Button("OK") { done(name.wrappedValue) }
            Button("Cancel", role: .cancel) {}
        }
    }
}
