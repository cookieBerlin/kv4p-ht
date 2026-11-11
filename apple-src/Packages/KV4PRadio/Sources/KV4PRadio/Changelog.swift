import Foundation

/// The changelog the app bundles (ADR-0069), read as the few blocks it is written in: headings, list items and
/// paragraphs. Their text keeps its inline Markdown, such as `**bold**`, for the view to show.
public struct Changelog: Sendable, Equatable {
    public enum Block: Sendable, Equatable, Hashable {
        case heading(level: Int, text: String)
        case item(String)
        case paragraph(String)
    }

    /// The section of a TestFlight build: its heading, such as `0.1 (20261101.2216) – 2026-11-01`, and what is below
    /// it up to the next section.
    public struct Release: Sendable, Equatable, Identifiable {
        public let title: String
        public let blocks: [Block]

        public var id: String { title }
    }

    public let blocks: [Block]

    public init(markdown: String) {
        var blocks: [Block] = []
        // The item or paragraph that the next line of text continues.
        var open: Block?
        func close() {
            if let block = open { blocks.append(block) }
            open = nil
        }
        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                close()
            } else if let heading = Self.heading(line) {
                close()
                blocks.append(heading)
            } else if let item = Self.item(line) {
                close()
                open = .item(item)
            } else {
                switch open {
                case .item(let text): open = .item(text + " " + line)
                case .paragraph(let text): open = .paragraph(text + " " + line)
                default: open = .paragraph(line)
                }
            }
        }
        close()
        self.blocks = blocks
    }

    /// The section whose heading names `build` in parentheses.
    public func release(build: String) -> Release? {
        guard
            let start = blocks.firstIndex(where: {
                if case .heading(Self.releaseLevel, let text) = $0 { text.contains("(\(build))") } else { false }
            }),
            case .heading(_, let title) = blocks[start]
        else { return nil }
        let rest = blocks[(start + 1)...]
        let end =
            rest.firstIndex(where: {
                if case .heading(let level, _) = $0 { level <= Self.releaseLevel } else { false }
            }) ?? blocks.endIndex
        return Release(title: title, blocks: Array(blocks[(start + 1)..<end]))
    }

    /// What the app offers once at its start: the section of `build` after an update from another build. A first
    /// installation has seen no build yet, and is offered nothing.
    public func offer(build: String, lastSeenBuild: String?) -> Release? {
        guard let lastSeenBuild, lastSeenBuild != build else { return nil }
        return release(build: build)
    }

    /// The level of the heading of each build's section, below the title of the changelog.
    private static let releaseLevel = 2

    private static func heading(_ line: String) -> Block? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count), line.dropFirst(hashes.count).first == " " else { return nil }
        return .heading(level: hashes.count, text: line.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces))
    }

    private static func item(_ line: String) -> String? {
        guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
        return line.dropFirst(2).trimmingCharacters(in: .whitespaces)
    }
}
