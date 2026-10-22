import Foundation
import Testing
@testable import Kaset

struct YouTubeTimestampLinkerTests {
    private func seconds(in text: String) -> [Int] {
        YouTubeTimestampLinker.matches(in: text).map(\.seconds)
    }

    @Test("Finds minute:second and hour:minute:second timestamps")
    func findsTimestamps() {
        #expect(self.seconds(in: "0:00 Intro\n1:23 Setup\n12:05 Demo\n1:02:45 Outro") == [0, 83, 725, 3765])
    }

    @Test("Finds timestamps inside a sentence and next to punctuation")
    func findsInsideSentences() {
        #expect(self.seconds(in: "Skip to 2:30, then (4:15) and finally 10:00.") == [150, 255, 600])
    }

    @Test("Ignores clock times, ratios, versions and decimals")
    func ignoresLookalikes() {
        #expect(self.seconds(in: "Doors at 10:30pm, or 7:15 PM, ratio 16:9, v2:5, 3.45:12").isEmpty)
        #expect(self.seconds(in: "12:61 and 5:7 are not timestamps").isEmpty)
    }

    @Test("Does not match inside longer digit or colon runs")
    func ignoresPartialMatches() {
        #expect(self.seconds(in: "123:45 and 1:23:45:67").isEmpty)
    }

    @Test("Each timestamp becomes a seek link and the text is unchanged")
    func buildsLinks() {
        let text = "Intro 0:30 then 1:05:00!"
        let attributed = YouTubeTimestampLinker.attributed(text)

        #expect(String(attributed.characters) == text)
        let links = attributed.runs.compactMap(\.link)
        #expect(links.compactMap { YouTubeTimestampLinker.seconds(from: $0) } == [30, 3900])
    }

    @Test("Text without timestamps has no links")
    func noLinksWithoutTimestamps() {
        let attributed = YouTubeTimestampLinker.attributed("Nothing to see here")

        #expect(attributed.runs.compactMap(\.link).isEmpty)
    }

    @Test("Only seek-scheme URLs are treated as seeks")
    func parsesOnlySeekLinks() throws {
        #expect(try YouTubeTimestampLinker.seconds(from: #require(URL(string: "kaset-seek://83"))) == 83)
        #expect(try YouTubeTimestampLinker.seconds(from: #require(URL(string: "https://example.com/83"))) == nil)
        #expect(try YouTubeTimestampLinker.seconds(from: #require(URL(string: "kaset-seek://abc"))) == nil)
    }
}
