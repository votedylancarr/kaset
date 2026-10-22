import Foundation
import Testing
@testable import Kaset

struct YouTubeDateFormatterTests {
    private let english = Locale(identifier: "en_US")

    private func format(_ iso: String) -> String {
        guard let date = YouTubeDateFormatter.date(fromISODay: iso) else { return "nil" }
        return YouTubeDateFormatter.absoluteString(from: date, locale: self.english)
    }

    @Test("Formats the long English date with an ordinal day")
    func formatsEnglish() {
        #expect(self.format("2026-10-31") == "October 31st, 2026")
        #expect(self.format("2024-01-01") == "January 1st, 2024")
        #expect(self.format("2025-03-02") == "March 2nd, 2025")
        #expect(self.format("2025-03-03") == "March 3rd, 2025")
        #expect(self.format("2025-03-04") == "March 4th, 2025")
    }

    @Test("Teens take th, not st, nd or rd")
    func ordinalTeens() {
        for (day, suffix) in [(11, "th"), (12, "th"), (13, "th"), (21, "st"), (22, "nd"), (23, "rd"), (30, "th")] {
            #expect(YouTubeDateFormatter.ordinalSuffix(for: day) == suffix)
        }
    }

    @Test("Other languages use their locale's long date, without an English ordinal")
    func formatsOtherLocales() throws {
        let date = try #require(YouTubeDateFormatter.date(fromISODay: "2026-10-31"))
        let german = YouTubeDateFormatter.absoluteString(from: date, locale: Locale(identifier: "de_DE"))

        #expect(german.contains("31"))
        #expect(german.contains("2026"))
        #expect(!german.contains("31st"))
    }

    @Test("The day does not shift with the viewer's time zone")
    func dayIsTimeZoneIndependent() throws {
        let date = try #require(YouTubeDateFormatter.date(fromISODay: "2026-10-31T23:30:00-07:00"))
        #expect(YouTubeDateFormatter.absoluteString(from: date, locale: self.english) == "October 31st, 2026")
    }

    @Test("Reads absolute dates from watch-page text and ignores relative text")
    func parsesWatchPageText() {
        func formatted(_ text: String) -> String? {
            YouTubeDateFormatter.date(fromWatchPageText: text)
                .map { YouTubeDateFormatter.absoluteString(from: $0, locale: self.english) }
        }
        #expect(formatted("Oct 31, 2026") == "October 31st, 2026")
        #expect(formatted("Premiered Sep 1, 2025") == "September 1st, 2025")
        #expect(formatted("Streamed live on Dec 22, 2024") == "December 22nd, 2024")
        #expect(formatted("3 days ago") == nil)
        #expect(formatted("Started streaming 2 hours ago") == nil)
    }

    @Test("Rejects impossible or malformed dates")
    func rejectsBadDates() {
        #expect(YouTubeDateFormatter.date(fromISODay: "2026-13-01") == nil)
        #expect(YouTubeDateFormatter.date(fromISODay: "2026-10") == nil)
        #expect(YouTubeDateFormatter.date(fromISODay: "not a date") == nil)
        #expect(YouTubeDateFormatter.date(fromWatchPageText: "Foo 40, 2026") == nil)
    }

    @Test("Reads the publish day from a player response, falling back to the upload day")
    func parsesPlayerResponse() {
        func renderer(_ fields: [String: String]) -> [String: Any] {
            ["microformat": ["playerMicroformatRenderer": fields]]
        }
        let publish = YouTubeDateFormatter.publishDate(fromPlayerResponse: renderer(["publishDate": "2026-10-31T09:00:00-07:00"]))
        let upload = YouTubeDateFormatter.publishDate(fromPlayerResponse: renderer(["uploadDate": "2025-05-17"]))

        #expect(publish.map { YouTubeDateFormatter.absoluteString(from: $0, locale: self.english) } == "October 31st, 2026")
        #expect(upload.map { YouTubeDateFormatter.absoluteString(from: $0, locale: self.english) } == "May 17th, 2025")
        #expect(YouTubeDateFormatter.publishDate(fromPlayerResponse: [:]) == nil)
    }

    @Test("The watch-next parser exposes the page's absolute date next to the relative one")
    func watchNextParserKeepsBothDates() {
        let response: [String: Any] = [
            "contents": ["twoColumnWatchNextResults": ["results": ["results": ["contents": [
                ["videoPrimaryInfoRenderer": [
                    "title": ["simpleText": "A video"],
                    "relativeDateText": ["simpleText": "3 days ago"],
                    "dateText": ["simpleText": "Oct 31, 2026"],
                ]],
            ]]]]],
        ]

        let data = WatchNextParser.parse(response)

        #expect(data.publishedText == "3 days ago")
        #expect(data.publishedDate.map { YouTubeDateFormatter.absoluteString(from: $0, locale: self.english) } == "October 31st, 2026")
    }
}
