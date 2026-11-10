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
    @Environment(\.dismiss) private var dismiss

    private var targetGroup: String { inGroup ? group.trimmingCharacters(in: .whitespaces) : "" }
    private var preview: RepeaterImportPreview? {
        csv.flatMap { model.importPreview($0, of: list, group: targetGroup) }
    }
    private var canImport: Bool { preview?.memories.isEmpty == false && (!inGroup || !targetGroup.isEmpty) }

    var body: some View {
        Form {
            Section("CSV file") {
                Text(instructions)
                Text(link)
                if !model.canImportRepeaters {
                    Text("Connect the radio first, so that only repeaters it can receive are imported.")
                        .foregroundStyle(.red)
                }
                Button("Choose file…", systemImage: "doc") { isChoosingFile = true }
                    .disabled(!model.canImportRepeaters)
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
                    Task { await model.importRepeaters(csv, of: list, group: group) }
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
