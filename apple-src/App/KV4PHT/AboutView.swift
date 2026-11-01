import KV4PRadio
import SwiftUI

/// The About window: version, build, the firmware the app ships and the licences.
struct AboutView: View {
    private let about = AboutInfo(info: Bundle.main.infoDictionary ?? [:])
    @State private var shown: LicenceFile?

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 40))
                    Text("kv4p HT").font(.title)
                    Text(about.version)
                    Text(about.firmware).foregroundStyle(.secondary)
                    if let url = URL(string: AboutInfo.sourceAddress) {
                        Link("Source code", destination: url)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            Section("Licences") {
                ForEach(AboutInfo.components) { component in
                    LabeledContent {
                        Button(component.licence.title) { shown = LicenceFile(name: component.licence.textFile) }
                            .buttonStyle(.borderless)
                    } label: {
                        Text(component.name)
                        Text(component.note)
                    }
                }
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
            .frame(minWidth: 480, minHeight: 560)
        #else
            .navigationTitle("About")
        #endif
        .sheet(item: $shown) { LicenceText(file: $0) }
    }
}

/// A licence text in the app bundle.
private struct LicenceFile: Identifiable {
    let name: String
    var id: String { name }
}

private struct LicenceText: View {
    let file: LicenceFile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .trailing) {
            ScrollView {
                Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding()
        #if os(macOS)
            .frame(minWidth: 600, minHeight: 500)
        #endif
    }

    private var text: String {
        Bundle.main.url(forResource: file.name, withExtension: nil)
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "The licence text is missing."
    }
}
