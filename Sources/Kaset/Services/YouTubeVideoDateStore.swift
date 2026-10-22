import Foundation
import Observation

// MARK: - YouTubeVideoDateStore

/// Exact publish dates for videos in lists that only carry relative dates (the watch
/// page's related rail). Dates are fetched lazily as rows appear, a few at a time,
/// and remembered across launches since a publish date never changes.
@MainActor
@Observable
final class YouTubeVideoDateStore {
    static let shared = YouTubeVideoDateStore()

    private static let defaultsKey = "youtube.publishDates"
    private static let maxStoredDates = 4000
    private static let maxConcurrentRequests = 3

    private(set) var dates: [String: Date] = [:]

    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private var failed: Set<String> = []
    @ObservationIgnored private var activeRequests = 0
    @ObservationIgnored private var waiting: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
        self.dates = stored.compactMapValues { YouTubeDateFormatter.date(fromISODay: $0) }
    }

    func date(for videoId: String) -> Date? {
        self.dates[videoId]
    }

    /// Fetches `videoId`'s publish date unless it is known, in flight, or already failed
    /// this session.
    func load(videoId: String, client: any YouTubeClientProtocol) async {
        guard self.dates[videoId] == nil, !self.inFlight.contains(videoId), !self.failed.contains(videoId) else {
            return
        }
        self.inFlight.insert(videoId)
        defer { self.inFlight.remove(videoId) }

        await self.acquireSlot()
        defer { self.releaseSlot() }
        guard !Task.isCancelled else { return }

        if let date = try? await client.getVideoPublishDate(videoId: videoId) {
            self.dates[videoId] = date
            self.persist()
        } else if !Task.isCancelled {
            self.failed.insert(videoId)
        }
    }

    // MARK: - Concurrency limit

    private func acquireSlot() async {
        if self.activeRequests < Self.maxConcurrentRequests {
            self.activeRequests += 1
            return
        }
        await withCheckedContinuation { self.waiting.append($0) }
    }

    private func releaseSlot() {
        if self.waiting.isEmpty {
            self.activeRequests -= 1
        } else {
            self.waiting.removeFirst().resume()
        }
    }

    // MARK: - Persistence

    private func persist() {
        if self.dates.count > Self.maxStoredDates {
            for key in self.dates.keys.prefix(self.dates.count - Self.maxStoredDates + 500) {
                self.dates.removeValue(forKey: key)
            }
        }
        var stored: [String: String] = [:]
        let calendar = Calendar(identifier: .gregorian)
        for (videoId, date) in self.dates {
            var utc = calendar
            utc.timeZone = .gmt
            let parts = utc.dateComponents([.year, .month, .day], from: date)
            if let year = parts.year, let month = parts.month, let day = parts.day {
                stored[videoId] = String(format: "%04d-%02d-%02d", year, month, day)
            }
        }
        self.defaults.set(stored, forKey: Self.defaultsKey)
    }
}
