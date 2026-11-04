import KV4PRadio
import SwiftUI
import UniformTypeIdentifiers

/// The assistant that adds repeaters from a RepeaterBook CSV export: file, what it would add, target group.
struct RepeaterImportView: View {
    let model: RadioViewModel
    @State private var isChoosingFile = false
    @State private var fileName: String?
    @State private var csv: String?
    @State private var group = ""
    /// Numbers the chosen files, so that the group field starts anew with the name of each.
    @State private var fileNumber = 0
    @State private var cannotRead = false
    @Environment(\.dismiss) private var dismiss

    private var targetGroup: String { group.trimmingCharacters(in: .whitespaces) }
    private var preview: RepeaterBookPreview? { csv.flatMap { model.importPreview($0, group: targetGroup) } }

    var body: some View {
        Form {
            Section("CSV file") {
                Text(
                    "Download the CSV export of a repeater list from RepeaterBook in your browser, then choose the file."
                )
                Text("[Open RepeaterBook](https://www.repeaterbook.com)")
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
                        GroupField(groups: model.groups, group: $group).id(fileNumber)
                        Text(preview.summary)
                    } else {
                        Text("This file is not a RepeaterBook CSV export.").foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
            .frame(minWidth: 460, minHeight: 360)
        #endif
        .navigationTitle("Import from RepeaterBook")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Import") {
                    let csv = csv ?? ""
                    let group = targetGroup
                    Task { await model.importRepeaterBook(csv, group: group) }
                    dismiss()
                }
                .disabled(preview?.memories.isEmpty != false)
            }
        }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            csv = try? String(contentsOf: url, encoding: .utf8)
            cannotRead = csv == nil
            fileName = url.lastPathComponent
            group = url.deletingPathExtension().lastPathComponent
            fileNumber += 1
        }
    }
}
