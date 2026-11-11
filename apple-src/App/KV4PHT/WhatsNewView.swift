import KV4PRadio
import SwiftUI

/// The changelog the app bundles (ADR-0069), and the section of this build that the app offers once after an update.
enum BundledChangelog {
    static let changelog = Changelog(
        markdown: Bundle.main.url(forResource: "CHANGELOG", withExtension: "md")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    )

    /// The build seen at the last start, on this device only.
    private static let lastSeenBuildKey = "lastSeenBuild"

    /// The section of this build after an update from another one, and nothing after the first installation. Remembers
    /// this build for the next start.
    static func offerAtStart(defaults: UserDefaults) -> Changelog.Release? {
        guard let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else { return nil }
        let offer = changelog.offer(build: build, lastSeenBuild: defaults.string(forKey: lastSeenBuildKey))
        defaults.set(build, forKey: lastSeenBuildKey)
        return offer
    }

    /// Everything below the changelog's own title.
    static var allBlocks: [Changelog.Block] {
        changelog.blocks.filter { if case .heading(1, _) = $0 { false } else { true } }
    }
}

/// What's new: the whole changelog from About, or the section of this build after an update. VoiceOver knows the
/// headings, so it can go from one build or group to the next.
struct WhatsNewView: View {
    let blocks: [Changelog.Block]
    @Environment(\.dismiss) private var dismiss

    init(blocks: [Changelog.Block] = BundledChangelog.allBlocks) {
        self.blocks = blocks
    }

    init(release: Changelog.Release) {
        blocks = [.heading(level: 2, text: release.title)] + release.blocks
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if blocks.isEmpty {
                        Text("The changelog is missing.")
                    }
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        ChangelogBlockView(block: block)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("What's New")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("whats-new-done")
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 520, minHeight: 560)
        #endif
    }
}

private struct ChangelogBlockView: View {
    let block: Changelog.Block

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(Self.inline(text))
                .font(level <= 2 ? .title2.bold() : .headline)
                .padding(.top, level <= 2 ? 14 : 4)
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
        case .item(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "•").accessibilityHidden(true)
                Text(Self.inline(text)).fixedSize(horizontal: false, vertical: true)
            }
        case .paragraph(let text):
            Text(Self.inline(text)).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The text with its inline Markdown, such as `**bold**` and `*Pages*`.
    private static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
