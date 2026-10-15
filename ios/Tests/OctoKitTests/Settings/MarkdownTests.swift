import Foundation
import Testing
@testable import OctoKit

@Suite struct MarkdownTests {
    typealias Span = Markdown.Span
    typealias Bullet = Markdown.Bullet

    private func plain(_ text: String) -> [Span] { [Span(text)] }

    @Test func headingsOneToThree() {
        #expect(Markdown.parse("# One\n## Two\n### Three\n#### Four") == [
            .heading(1, plain("One")), .heading(2, plain("Two")), .heading(3, plain("Three")),
            // Deeper headings read as the smallest.
            .heading(3, plain("Four")),
        ])
        #expect(Markdown.parse("## Title ##") == [.heading(2, plain("Title"))])
    }

    @Test func aHashWithoutASpaceIsNotAHeading() {
        #expect(Markdown.parse("#1 hits") == [.paragraph(plain("#1 hits"))])
        #expect(Markdown.parse("## C#") == [.heading(2, plain("C#"))])
        #expect(Markdown.parse("####### seven") == [.paragraph(plain("####### seven"))])
    }

    @Test func linesTogetherMakeOneParagraphAndABlankLineStartsAnother() {
        #expect(Markdown.parse("First line\nsame paragraph\n\nSecond") == [.paragraph(plain("First line same paragraph")), .paragraph(plain("Second"))])
        #expect(Markdown.parse("Windows\r\nlines") == [.paragraph(plain("Windows lines"))])
    }

    @Test func bulletsWithEveryMark() {
        #expect(Markdown.parse("- one\n* two\n+ three") == [.bullets([Bullet(plain("one")), Bullet(plain("two")), Bullet(plain("three"))])])
    }

    @Test func anIndentedBulletSitsUnderTheOneAbove() {
        #expect(Markdown.parse("- parent\n  - child\n  - second child\n      - deeper\n- next") == [
            .bullets([
                Bullet(plain("parent"), children: [Bullet(plain("child")), Bullet(plain("second child")), Bullet(plain("deeper"))]),
                Bullet(plain("next")),
            ]),
        ])
        #expect(Markdown.parse("- parent\n\t- tabbed") == [.bullets([Bullet(plain("parent"), children: [Bullet(plain("tabbed"))])])])
    }

    @Test func anIndentedLineCarriesItsBulletOn() {
        #expect(Markdown.parse("- a long line\n  that wraps\nAfter") == [.bullets([Bullet(plain("a long line that wraps"))]), .paragraph(plain("After"))])
    }

    @Test func rules() {
        #expect(Markdown.parse("a\n\n---\n\nb") == [.paragraph(plain("a")), .rule, .paragraph(plain("b"))])
        #expect(Markdown.parse("***\n_ _ _") == [.rule, .rule])
        #expect(Markdown.parse("* * *") == [.rule])
    }

    @Test func boldAndItalic() {
        #expect(Markdown.parseInline("a **bold** word") == [Span("a "), Span("bold", bold: true), Span(" word")])
        #expect(Markdown.parseInline("a __bold__") == [Span("a "), Span("bold", bold: true)])
        #expect(Markdown.parseInline("an *italic* word") == [Span("an "), Span("italic", italic: true), Span(" word")])
        #expect(Markdown.parseInline("an _italic_") == [Span("an "), Span("italic", italic: true)])
    }

    @Test func italicInsideBold() {
        #expect(Markdown.parseInline("**very *much* so**") == [Span("very ", bold: true), Span("much", bold: true, italic: true), Span(" so", bold: true)])
    }

    @Test func inlineCodeKeepsItsMarks() {
        #expect(Markdown.parseInline("run `a *b* c`") == [Span("run "), Span("a *b* c", code: true)])
    }

    @Test func links() {
        #expect(Markdown.parseInline("see [the site](https://example.org).")
            == [Span("see "), Span("the site", link: "https://example.org"), Span(".")])
        #expect(Markdown.parseInline("[**big**](https://x.y)") == [Span("big", bold: true, link: "https://x.y")])
    }

    @Test func bracketsThatAreNotLinksStayAsTheyAre() {
        #expect(Markdown.parseInline("Song [Remix] (Live)") == plain("Song [Remix] (Live)"))
        #expect(Markdown.parseInline("[] and [a](b c)") == plain("[] and [a](b c)"))
    }

    @Test func songTitlesWithMarksReadAsWritten() {
        for title in ["$UICIDE", "$uicideboy$", "F*ck It", "S*M*A*R*T", "*NSYNC", "5 * 3 = 15", "Hello*", "snake_case_title", "2 ** 8",
                      "_underscore at the start", "$100 Bill"] {
            #expect(Markdown.parseInline(title) == plain(title), "\(title)")
        }
    }

    @Test func aTitleWithMarksInsideAListItem() {
        #expect(Markdown.parse("- $UICIDE by *$uicideboy$*") == [.bullets([Bullet([Span("$UICIDE by "), Span("$uicideboy$", italic: true)])])])
    }

    @Test func aBackslashKeepsAMarkLiteral() {
        #expect(Markdown.parseInline("\\*not italic\\*") == plain("*not italic*"))
    }

    @Test func anUnclosedMarkIsPlainText() {
        #expect(Markdown.parseInline("**half bold") == plain("**half bold"))
        #expect(Markdown.parseInline("`half code") == plain("`half code"))
    }

    @Test func emptyTextHasNoBlocks() {
        #expect(Markdown.parse("").isEmpty)
        #expect(Markdown.parse("\n\n  \n").isEmpty)
    }
}

@Suite struct WhatsNewTests {
    @Test func aFreshInstallHasNoNews() {
        #expect(!WhatsNew.due(lastSeen: nil, current: 3, freshInstall: true))
    }

    @Test func theFirstUpdateSinceTheCardExistedShowsIt() {
        #expect(WhatsNew.due(lastSeen: nil, current: 3, freshInstall: false))
    }

    @Test func itShowsOncePerVersion() {
        #expect(WhatsNew.due(lastSeen: 2, current: 3, freshInstall: false))
        #expect(!WhatsNew.due(lastSeen: 3, current: 3, freshInstall: false))
    }

    @Test func theNotesArePlainWords() {
        for line in [WhatsNew.summary] + WhatsNew.notes.split(separator: "\n").map(String.init) {
            #expect(!line.contains("\u{2014}") && !line.contains("\u{2013}"), "\(line)")
        }
    }

    @Test func everyPartOfTheAppHasAHeadingAndItsLines() {
        let blocks = Markdown.parse(WhatsNew.notes)
        let headings = blocks.compactMap { block -> String? in
            if case .heading(_, let text) = block { return Markdown.plainText(text) }
            return nil
        }
        #expect(headings == ["Sound", "Library", "Playback", "Server", "Lyrics", "Offline", "Everyday touches", "Settings"])
        for (index, block) in blocks.enumerated() {
            guard case .heading(_, let text) = block else { continue }
            if index + 1 < blocks.count, case .bullets(let items) = blocks[index + 1] {
                #expect(!items.isEmpty, "\(Markdown.plainText(text))")
            } else {
                Issue.record("\(Markdown.plainText(text)) has no list")
            }
        }
        for block in blocks {
            let words: [String] = switch block {
            case .heading(_, let text), .paragraph(let text): [Markdown.plainText(text)]
            case .bullets(let items): items.map { Markdown.plainText($0.text) }
            case .rule: []
            }
            for word in words { #expect(!word.contains("**") && !word.contains("`"), "\(word)") }
        }
    }

    @Test func eachPartHasItsNumberOfLines() {
        let blocks = Markdown.parse(WhatsNew.notes)
        var counts: [Int] = []
        for (index, block) in blocks.enumerated() {
            guard case .heading = block, index + 1 < blocks.count, case .bullets(let items) = blocks[index + 1] else { continue }
            #expect(items.allSatisfy { $0.children.isEmpty })
            counts.append(items.count)
        }
        #expect(counts == [4, 8, 8, 9, 4, 5, 10, 4])
        #expect(counts.reduce(0, +) == 52)
    }

    @Test func theHomeCardLineIsShort() {
        #expect(WhatsNew.summary.count <= 70)
    }
}
