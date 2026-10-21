import Foundation
import Testing
@testable import Kaset

@Suite("YouTube queue", .serialized, .tags(.service), .timeLimit(.minutes(1)))
@MainActor
struct YouTubeQueueTests {
    private let controller = MockYouTubeWatchPlaybackController()

    private func makeSUT(autoplay: Bool = false) -> YouTubePlayerService {
        YouTubePlayerService(
            playbackController: self.controller,
            shouldPopOutOnNavigateAway: { true },
            shouldAutoplayNext: { autoplay },
            shouldPopOutWhenCovered: { false }
        )
    }

    private func video(_ id: String, isShort: Bool = false) -> YouTubeVideo {
        MockYouTubeClient.makeVideo(videoId: id, isShort: isShort)
    }

    @Test("Add to Queue appends once and ignores the playing video and Shorts")
    func addToQueueRules() {
        let sut = self.makeSUT()
        sut.play(video: self.video("now"))

        sut.addToQueue(self.video("a"))
        sut.addToQueue(self.video("b"))
        sut.addToQueue(self.video("a"))
        sut.addToQueue(self.video("now"))
        sut.addToQueue(self.video("short", isShort: true))

        #expect(sut.userQueue.map(\.videoId) == ["a", "b"])
    }

    @Test("Play Next goes to the front and moves a queued video there")
    func playNextGoesFirst() {
        let sut = self.makeSUT()
        sut.addToQueue(self.video("a"))
        sut.addToQueue(self.video("b"))

        sut.playNext(self.video("c"))
        sut.playNext(self.video("b"))

        #expect(sut.userQueue.map(\.videoId) == ["b", "c", "a"])
    }

    @Test("Reordering, removing and clearing change the queue as asked")
    func editQueue() {
        let sut = self.makeSUT()
        for id in ["a", "b", "c"] {
            sut.addToQueue(self.video(id))
        }

        sut.moveInQueue(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(sut.userQueue.map(\.videoId) == ["c", "a", "b"])

        sut.removeFromQueue(self.video("a"))
        #expect(sut.userQueue.map(\.videoId) == ["c", "b"])

        sut.clearQueue()
        #expect(sut.userQueue.isEmpty)
    }

    @Test("The queue comes before related videos")
    func queueBeatsRelated() {
        let sut = self.makeSUT()
        sut.play(video: self.video("now"))
        sut.setUpNext([self.video("related")])
        #expect(sut.nextVideoCandidate?.videoId == "related")

        sut.addToQueue(self.video("queued"))

        #expect(sut.nextVideoCandidate?.videoId == "queued")
    }

    @Test("Skipping plays the queued video first, and it leaves the queue")
    func skipUsesQueue() async {
        let sut = self.makeSUT()
        sut.play(video: self.video("now"))
        sut.setUpNext([self.video("related")])
        sut.addToQueue(self.video("a"))
        sut.addToQueue(self.video("b"))

        await sut.skipForward()

        #expect(sut.currentVideo?.videoId == "a")
        #expect(sut.userQueue.map(\.videoId) == ["b"])
    }

    @Test("Once the queue is empty, skipping falls back to related videos")
    func skipFallsBackToRelated() async {
        let sut = self.makeSUT()
        sut.play(video: self.video("now"))
        sut.setUpNext([self.video("related")])
        sut.addToQueue(self.video("a"))

        await sut.skipForward()
        await sut.skipForward()

        #expect(sut.currentVideo?.videoId == "related")
        #expect(sut.userQueue.isEmpty)
    }

    @Test("Autoplay counts down to the queued video")
    func autoplayUsesQueue() async throws {
        let sut = self.makeSUT(autoplay: true)
        sut.play(video: self.video("now"))
        sut.setUpNext([self.video("related")])
        sut.addToQueue(self.video("queued"))
        sut.updatePlaybackState(.init(isPlaying: true, progress: 59, duration: 60, videoId: "now", title: nil, isAd: false))

        sut.handleVideoEnded(videoId: "now")
        try await Task.sleep(for: .milliseconds(100))

        #expect(sut.autoplayCountdown?.video.videoId == "queued")
        sut.cancelAutoplayCountdown()
    }

    @Test("Playing a queued video now removes only that one")
    func playQueuedVideoNow() {
        let sut = self.makeSUT()
        sut.play(video: self.video("now"))
        sut.addToQueue(self.video("a"))
        sut.addToQueue(self.video("b"))

        sut.playQueuedVideo(self.video("b"))

        #expect(sut.currentVideo?.videoId == "b")
        #expect(sut.userQueue.map(\.videoId) == ["a"])
        #expect(self.controller.loadedVideoIds.last == "b")
    }
}
