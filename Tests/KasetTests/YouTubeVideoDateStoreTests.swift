import Foundation
import Testing
@testable import Kaset

@MainActor
struct YouTubeVideoDateStoreTests {
    private func makeStore() -> YouTubeVideoDateStore {
        YouTubeVideoDateStore(defaults: UserDefaults(suiteName: "YouTubeVideoDateStoreTests-\(UUID().uuidString)") ?? .standard)
    }

    @Test("A fetched date is remembered and not fetched twice")
    func fetchesOnce() async {
        let client = MockYouTubeClient()
        client.publishDays["abc"] = "2026-10-31"
        let store = self.makeStore()

        await store.load(videoId: "abc", client: client)
        await store.load(videoId: "abc", client: client)

        #expect(store.date(for: "abc") != nil)
        #expect(client.publishDateCallCount == 1)
    }

    @Test("A video with no date is not asked for again this session")
    func failureIsNotRetried() async {
        let client = MockYouTubeClient()
        let store = self.makeStore()

        await store.load(videoId: "abc", client: client)
        await store.load(videoId: "abc", client: client)

        #expect(store.date(for: "abc") == nil)
        #expect(client.publishDateCallCount == 1)
    }

    @Test("Known dates survive a restart")
    func persists() async throws {
        let suite = try #require(UserDefaults(suiteName: "YouTubeVideoDateStoreTests-persist-\(UUID().uuidString)"))
        let first = YouTubeVideoDateStore(defaults: suite)
        let client = MockYouTubeClient()
        client.publishDays["abc"] = "2025-05-17"
        await first.load(videoId: "abc", client: client)

        let second = YouTubeVideoDateStore(defaults: suite)

        #expect(second.date(for: "abc") == YouTubeDateFormatter.date(fromISODay: "2025-05-17"))
    }
}
