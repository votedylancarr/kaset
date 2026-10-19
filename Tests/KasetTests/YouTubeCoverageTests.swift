import Foundation
import Testing
@testable import Kaset

@Suite("YouTube pop-out when covered", .serialized, .tags(.service), .timeLimit(.minutes(1)))
@MainActor
struct YouTubeCoverageTests {
    private let controller = MockYouTubeWatchPlaybackController()

    private func makePlayingSUT(popOutWhenCovered: Bool = true) -> YouTubePlayerService {
        let sut = YouTubePlayerService(
            playbackController: self.controller,
            shouldPopOutOnNavigateAway: { true },
            shouldAutoplayNext: { false },
            shouldPopOutWhenCovered: { popOutWhenCovered }
        )
        sut.play(video: MockYouTubeClient.makeVideo(videoId: "a"))
        sut.updatePlaybackState(.init(isPlaying: true, progress: 5, duration: 60, videoId: "a", title: nil, isAd: false))
        return sut
    }

    @Test("A covered window pops a playing video out")
    func coveredPopsOut() {
        let sut = self.makePlayingSUT()

        sut.applyMainWindowCoverage(isCovered: true)

        #expect(sut.surfaceLocation == .floating)
        #expect(sut.isPoppedOutForCoverage)
    }

    @Test("Becoming visible again requests docking back")
    func visibleDocksBack() {
        let sut = self.makePlayingSUT()
        sut.applyMainWindowCoverage(isCovered: true)

        sut.applyMainWindowCoverage(isCovered: false)

        #expect(sut.popInRequest?.videoId == "a")
        #expect(!sut.isPoppedOutForCoverage)
    }

    @Test("A paused video is not popped out")
    func pausedVideoStays() {
        let sut = self.makePlayingSUT()
        sut.updatePlaybackState(.init(isPlaying: false, progress: 5, duration: 60, videoId: "a", title: nil, isAd: false))

        sut.applyMainWindowCoverage(isCovered: true)

        #expect(sut.surfaceLocation == .inline)
        #expect(!sut.isPoppedOutForCoverage)
    }

    @Test("The setting off disables the behavior")
    func settingOffDoesNothing() {
        let sut = self.makePlayingSUT(popOutWhenCovered: false)

        sut.applyMainWindowCoverage(isCovered: true)

        #expect(sut.surfaceLocation == .inline)
    }

    @Test("A pop-out the user made themselves is not docked back on uncover")
    func manualPopOutIsNotUndone() {
        let sut = self.makePlayingSUT()
        sut.popOutToWindow()

        sut.applyMainWindowCoverage(isCovered: false)

        #expect(sut.surfaceLocation == .floating)
        #expect(sut.popInRequest == nil)
    }

    @Test("A Dock click docks a floating video back when its page is open")
    func reopenDocksVideoOnItsPage() {
        let sut = self.makePlayingSUT()
        sut.activeInlineVideoId = "a"
        sut.applyMainWindowCoverage(isCovered: true)

        sut.dockFloatingVideoOnItsPage()

        #expect(sut.surfaceLocation == .inline)
        #expect(!sut.isPoppedOutForCoverage)
    }

    @Test("A Dock click leaves a video that floats because you navigated away")
    func reopenKeepsNavigateAwayPopOut() {
        let sut = self.makePlayingSUT()
        sut.activeInlineVideoId = nil
        sut.popOutToWindow()

        sut.dockFloatingVideoOnItsPage()

        #expect(sut.surfaceLocation == .floating)
    }

    @Test("Closing the floating window clears the coverage pop-out")
    func stopClearsFlag() {
        let sut = self.makePlayingSUT()
        sut.applyMainWindowCoverage(isCovered: true)

        sut.stop()
        sut.applyMainWindowCoverage(isCovered: false)

        #expect(!sut.isPoppedOutForCoverage)
        #expect(sut.popInRequest == nil)
    }
}
