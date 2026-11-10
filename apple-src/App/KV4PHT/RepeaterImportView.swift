import KV4PAudio
import KV4PRadio
import SwiftUI
import UniformTypeIdentifiers

/// The assistant that adds repeaters from a list exported in the browser: file, what it would add, target group.
struct RepeaterImportView: View {
    let model: RadioViewModel
    let list: RepeaterList
    @State private var isChoosingFile = false
    @State private var fileName: String?
    @State private var csv: String?
    @State private var inGroup = true
    @State private var group = ""
    /// Numbers the chosen files, so that the group field starts anew with the name of each.
    @State private var fileNumber = 0
    @State private var cannotRead = false
    @State private var setsAccessTone = true
    @State private var accessTone = ImportAccessTone.standard
    @Environment(\.dismiss) private var dismiss

    private var targetGroup: String { inGroup ? group.trimmingCharacters(in: .whitespaces) : "" }
    private var preview: RepeaterImportPreview? {
        csv.flatMap { model.importPreview($0, of: list, group: targetGroup, accessTone: chosenAccessTone) }
    }
    private var chosenAccessTone: ImportAccessTone? { list == .darc && setsAccessTone ? accessTone : nil }
    private var canImport: Bool {
        guard let preview, !preview.memories.isEmpty || !preview.completed.isEmpty else { return false }
        return !inGroup || !targetGroup.isEmpty
    }

    var body: some View {
        Form {
            Section("CSV file") {
                Text(instructions)
                Text(link)
                Button("Choose file…", systemImage: "doc") { isChoosingFile = true }
                if let fileName {
                    LabeledContent("File", value: fileName)
                }
                if cannotRead {
                    Text("This file cannot be read.").foregroundStyle(.red)
                }
            }
            if csv != nil {
                Section("Result") {
                    if let preview {
                        Toggle("Add to a group", isOn: $inGroup)
                        if inGroup {
                            GroupField(groups: model.groups, group: $group, allowsNone: false).id(fileNumber)
                        }
                        if list == .darc {
                            accessToneChoice
                        }
                        Text(preview.summary)
                    } else {
                        Text(list.notThisList).foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
            .frame(minWidth: 460, minHeight: 360)
        #endif
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Import") {
                    let csv = csv ?? ""
                    let group = targetGroup
                    let list = list
                    let accessTone = chosenAccessTone
                    Task { await model.importRepeaters(csv, of: list, group: group, accessTone: accessTone) }
                    dismiss()
                }
                .disabled(!canImport)
            }
        }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            csv = (try? Data(contentsOf: url)).map(RepeaterImport.text)
            cannotRead = csv == nil
            fileName = url.lastPathComponent
            group = url.deletingPathExtension().lastPathComponent
            fileNumber += 1
        }
    }

    /// The access tone of the new repeaters, as most German ones need one.
    @ViewBuilder private var accessToneChoice: some View {
        Toggle("Set the access tone", isOn: $setsAccessTone)
        if setsAccessTone {
            Picker("Access tone", selection: $accessTone.hz) {
                ForEach(AccessTone.frequencies, id: \.self) { Text("\($0) Hz") }
            }
            Picker("Tone length", selection: $accessTone.lengthMs) {
                ForEach(AccessTone.lengthsMs, id: \.self) { Text(AccessTone.lengthLabel($0)) }
            }
        }
    }

    private var title: LocalizedStringKey {
        switch list {
        case .repeaterBook: "Import from RepeaterBook"
        case .darc: "Import from DARC"
        }
    }

    private var instructions: LocalizedStringKey {
        switch list {
        case .repeaterBook:
            "Download the CSV export of a repeater list from RepeaterBook in your browser, then choose the file."
        case .darc:
            "Download the CSV export of a repeater list from the DARC repeater lists in your browser, then choose the file."
        }
    }

    private var link: LocalizedStringKey {
        switch list {
        case .repeaterBook: "[Open RepeaterBook](https://www.repeaterbook.com)"
        case .darc: "[Open the DARC repeater lists](https://relaislisten.darc.de)"
        }
    }
}
