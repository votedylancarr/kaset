import Foundation
import Testing
@testable import Kaset

@Suite("YouTube autoplay", .serialized, .tags(.service), .timeLimit(.minutes(1)))
@MainActor
struct YouTubeAutoplayTests {
    private let controller = MockYouTubeWatchPlaybackController()

    private func makeSUT(autoplay: Bool) -> YouTubePlayerService {
        YouTubePlayerService(
            playbackController: self.controller,
            shouldPopOutOnNavigateAway: { true },
            shouldAutoplayNext: { autoplay }
        )
    }

    private func finishVideo(_ id: String, on sut: YouTubePlayerService) {
        sut.play(video: MockYouTubeClient.makeVideo(videoId: id))
        sut.updatePlaybackState(.init(
            isPlaying: true, progress: 59, duration: 60,
            videoId: id, title: nil, isAd: false
        ))
        sut.handleVideoEnded(videoId: id)
    }

    @Test("An ended video queues the first up-next video for autoplay")
    func endedVideoStartsCountdown() async throws {
        let sut = self.makeSUT(autoplay: true)
        sut.play(video: MockYouTubeClient.makeVideo(videoId: "a"))
        sut.setUpNext([MockYouTubeClient.makeVideo(videoId: "b"), MockYouTubeClient.makeVideo(videoId: "c")])
        sut.updatePlaybackState(.init(isPlaying: true, progress: 59, duration: 60, videoId: "a", title: nil, isAd: false))

        sut.handleVideoEnded(videoId: "a")
        try await Task.sleep(for: .milliseconds(100))

        let countdown = try #require(sut.autoplayCountdown)
        #expect(countdown.afterVideoId == "a")
        #expect(countdown.video.videoId == "b")
        sut.cancelAutoplayCountdown()
    }

    @Test("Autoplay off never starts a countdown")
    func disabledAutoplayDoesNothing() async throws {
        let sut = self.makeSUT(autoplay: false)
        sut.play(video: MockYouTubeClient.makeVideo(videoId: "a"))
        sut.setUpNext([MockYouTubeClient.makeVideo(videoId: "b")])
        sut.updatePlaybackState(.init(isPlaying: true, progress: 59, duration: 60, videoId: "a", title: nil, isAd: false))

        sut.handleVideoEnded(videoId: "a")
        try await Task.sleep(for: .milliseconds(100))

        #expect(sut.autoplayCountdown == nil)
    }

    @Test("Cancelling stops autoplay and the video never advances")
    func cancelStopsAutoplay() async throws {
        let sut = self.makeSUT(autoplay: true)
        sut.play(video: MockYouTubeClient.makeVideo(videoId: "a"))
        sut.setUpNext([MockYouTubeClient.makeVideo(videoId: "b")])
        sut.updatePlaybackState(.init(isPlaying: true, progress: 59, duration: 60, videoId: "a", title: nil, isAd: false))
        sut.handleVideoEnded(videoId: "a")
        try await Task.sleep(for: .milliseconds(100))
        #expect(sut.autoplayCountdown != nil)

        sut.cancelAutoplayCountdown()

        #expect(sut.autoplayCountdown == nil)
        #expect(sut.currentVideo?.videoId == "a")
    }

    @Test("Play Now advances immediately and clears the countdown")
    func playNowAdvances() async throws {
        let sut = self.makeSUT(autoplay: true)
        sut.play(video: MockYouTubeClient.makeVideo(videoId: "a"))
        sut.setUpNext([MockYouTubeClient.makeVideo(videoId: "b")])
        sut.updatePlaybackState(.init(isPlaying: true, progress: 59, duration: 60, videoId: "a", title: nil, isAd: false))
        sut.handleVideoEnded(videoId: "a")
        try await Task.sleep(for: .milliseconds(100))

        sut.playAutoplayCandidateNow()

        #expect(sut.currentVideo?.videoId == "b")
        #expect(sut.autoplayCountdown == nil)
        #expect(self.controller.loadedVideoIds.last == "b")
    }

    @Test("Any new playback intent cancels a pending autoplay")
    func userIntentCancelsAutoplay() async throws {
        let sut = self.makeSUT(autoplay: true)
        sut.play(video: MockYouTubeClient.makeVideo(videoId: "a"))
        sut.setUpNext([MockYouTubeClient.makeVideo(videoId: "b")])
        sut.updatePlaybackState(.init(isPlaying: true, progress: 59, duration: 60, videoId: "a", title: nil, isAd: false))
        sut.handleVideoEnded(videoId: "a")
        try await Task.sleep(for: .milliseconds(100))
        #expect(sut.autoplayCountdown != nil)

        sut.seek(to: 0)

        #expect(sut.autoplayCountdown == nil)
        #expect(sut.currentVideo?.videoId == "a")
    }

    @Test("Shorts are never autoplayed")
    func shortsAreSkipped() async throws {
        let sut = self.makeSUT(autoplay: true)
        sut.play(video: MockYouTubeClient.makeVideo(videoId: "s", isShort: true))
        sut.setUpNext([MockYouTubeClient.makeVideo(videoId: "b")])
        sut.updatePlaybackState(.init(isPlaying: true, progress: 29, duration: 30, videoId: "s", title: nil, isAd: false))

        sut.handleVideoEnded(videoId: "s")
        try await Task.sleep(for: .milliseconds(100))

        #expect(sut.autoplayCountdown == nil)
    }
}
