import Testing

@testable import KV4PRadio

/// The changelog the app bundles (ADR-0069): a small reader for its headings, lists and paragraphs, and the section
/// of a build that the app offers once after an update.
@Suite("Changelog")
struct ChangelogTests {
    private static let text = """
        # Changelog

        What users notice, newest first.

        ## Unreleased

        ### Added

        - A map with the memories.
        - A page of the settings
          that switches APRS off.

        ## 2.0.0 (20261112.0930) – 2026-11-12

        ### Fixed

        * The frequency keeps its **last** digit.

        ## 0.1 (20261101.2216) – 2026-11-01

        ### Added

        - The first build.
        """

    @Test("headings, list items and paragraphs, with lines of one item or paragraph joined")
    func blocks() {
        let changelog = Changelog(markdown: Self.text)
        #expect(
            changelog.blocks == [
                .heading(level: 1, text: "Changelog"),
                .paragraph("What users notice, newest first."),
                .heading(level: 2, text: "Unreleased"),
                .heading(level: 3, text: "Added"),
                .item("A map with the memories."),
                .item("A page of the settings that switches APRS off."),
                .heading(level: 2, text: "2.0.0 (20261112.0930) – 2026-11-12"),
                .heading(level: 3, text: "Fixed"),
                .item("The frequency keeps its **last** digit."),
                .heading(level: 2, text: "0.1 (20261101.2216) – 2026-11-01"),
                .heading(level: 3, text: "Added"),
                .item("The first build."),
            ]
        )
    }

    @Test("a paragraph of several lines, and one right after a list or a heading")
    func paragraphs() {
        let changelog = Changelog(markdown: "Two\nlines.\n- An item.\nAfter it.\n## Head\nBelow it.\n\n\n")
        #expect(
            changelog.blocks == [
                .paragraph("Two lines."),
                .item("An item. After it."),
                .heading(level: 2, text: "Head"),
                .paragraph("Below it."),
            ]
        )
    }

    @Test("a line of hashes without a space, or more than six, is text")
    func notHeadings() {
        let changelog = Changelog(markdown: "#hashtag\n\n####### seven\n\n-not an item")
        #expect(changelog.blocks == [.paragraph("#hashtag"), .paragraph("####### seven"), .paragraph("-not an item")])
    }

    @Test("the section of a build, from its heading to the next of its level")
    func release() throws {
        let changelog = Changelog(markdown: Self.text)
        let release = try #require(changelog.release(build: "20261112.0930"))
        #expect(release.title == "2.0.0 (20261112.0930) – 2026-11-12")
        #expect(release.id == release.title)
        #expect(
            release.blocks == [.heading(level: 3, text: "Fixed"), .item("The frequency keeps its **last** digit.")]
        )
        let last = try #require(changelog.release(build: "20261101.2216"))
        #expect(last.blocks == [.heading(level: 3, text: "Added"), .item("The first build.")])
        #expect(changelog.release(build: "20261101") == nil)
        #expect(changelog.release(build: "Unreleased") == nil)
    }

    @Test("an update offers the section of its build once; a first installation offers nothing")
    func offer() throws {
        let changelog = Changelog(markdown: Self.text)
        let offered = try #require(changelog.offer(build: "20261112.0930", lastSeenBuild: "20261101.2216"))
        #expect(offered.title == "2.0.0 (20261112.0930) – 2026-11-12")
        #expect(changelog.offer(build: "20261112.0930", lastSeenBuild: "20261112.0930") == nil)
        #expect(changelog.offer(build: "20261112.0930", lastSeenBuild: nil) == nil)
        // A build without a section of its own, such as one from Xcode, has nothing to offer.
        #expect(changelog.offer(build: "7", lastSeenBuild: "20261101.2216") == nil)
    }
}
