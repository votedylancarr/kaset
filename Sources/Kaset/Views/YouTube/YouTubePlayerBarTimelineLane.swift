import SwiftUI

// MARK: - YouTubePlayerBarTimelineLane

/// The YouTube player bar's seek lane. This is the only YouTube player bar view that
/// observes `YouTubePlayerService.progress`, so each playback tick re-evaluates just this
/// lane instead of the whole bar. Nothing outside the lane reads its seek state, so the
/// state lives here and is discarded when an ad replaces the lane.
struct YouTubePlayerBarTimelineLane: View {
    let accent: Color
    let markers: [PlayerBarProgressMarker]
    let segments: [PlayerBarProgressSegment]
    let isLive: Bool
    let canSeek: Bool
    let onMarkerPreviewChange: (PlayerBarProgressMarker?) -> Void

    @Environment(YouTubePlayerService.self) private var youtubePlayer

    @State private var seekValue: Double = 0
    @State private var isSeeking = false
    @State private var seekHold = PlayerBarSeekHold()
    @State private var hoverFraction: Double?
    @State private var preview = YouTubeSeekPreviewModel()
    @State private var previewCardSize: CGSize = .zero

    var body: some View {
        PlayerBarProgressLane(
            fraction: self.displayFraction,
            accent: self.accent,
            elapsedText: PlayerBarSeekController.formatTime(self.progressTextValue),
            remainingText: "-\(PlayerBarSeekController.formatTime(max(0, self.youtubePlayer.duration - self.progressTextValue)))",
            markers: self.markers,
            segments: self.segments,
            isLive: self.isLive,
            canSeek: self.canSeek,
            isLoading: self.youtubePlayer.isPlaybackLoading,
            onScrub: { fraction in
                self.isSeeking = true
                self.seekValue = fraction
            },
            onCommit: self.performSeek,
            onMarkerPreviewChange: self.onMarkerPreviewChange,
            onHoverFractionChange: { self.hoverFraction = $0 }
        )
        .overlay(alignment: .topLeading) { self.seekPreviewOverlay }
        .task(id: self.youtubePlayer.storyboardSpec) {
            self.preview.configure(spec: self.youtubePlayer.storyboardSpec)
        }
        .onChange(of: self.previewFraction) { _, fraction in
            if let fraction {
                self.preview.show(fraction: fraction, duration: self.youtubePlayer.duration)
            } else {
                self.preview.hide()
            }
        }
        .onChange(of: self.youtubePlayer.progress) { _, newValue in
            self.reconcileHold(observedProgress: newValue)
            if !self.isSeeking, !self.seekHold.isActive, self.youtubePlayer.duration > 0 {
                self.seekValue = self.displayedPlaybackProgress / self.youtubePlayer.duration
            }
        }
        .onChange(of: self.youtubePlayer.duration) { _, newValue in
            self.reconcileHold(observedProgress: self.youtubePlayer.progress)
            if !self.isSeeking, !self.seekHold.isActive, newValue > 0 {
                self.seekValue = self.displayedPlaybackProgress / newValue
            }
        }
        .onChange(of: self.currentSeekIdentity) { _, _ in
            self.clearSeekHold()
        }
        .onChange(of: self.canSeek) { _, _ in
            self.clearSeekHold()
        }
        .onAppear {
            self.syncSeekValueFromDisplayedProgress()
        }
    }

    /// Fraction (0...1) to render: the live drag value while seeking, otherwise actual progress.
    private var displayFraction: Double {
        if self.isSeeking {
            return min(max(0, self.seekValue), 1)
        }
        guard self.youtubePlayer.duration > 0 else { return 0 }
        return min(max(0, self.displayedPlaybackProgress / self.youtubePlayer.duration), 1)
    }

    /// Where the preview should show: the scrub position while dragging, else the hover position.
    private var previewFraction: Double? {
        guard self.canSeek, !self.isLive, self.youtubePlayer.duration > 0 else { return nil }
        return self.isSeeking ? self.seekValue : self.hoverFraction
    }

    /// Thumbnail card above the lane, following the pointer and kept inside the lane's width.
    private var seekPreviewOverlay: some View {
        GeometryReader { geometry in
            if let fraction = self.previewFraction, self.preview.image != nil {
                let time = fraction * self.youtubePlayer.duration
                let halfWidth = self.previewCardSize.width / 2
                let centerX = geometry.size.width > self.previewCardSize.width
                    ? min(max(fraction * geometry.size.width, halfWidth), geometry.size.width - halfWidth)
                    : geometry.size.width / 2
                YouTubeSeekPreviewCard(
                    image: self.preview.image,
                    timeText: PlayerBarSeekController.formatTime(time),
                    chapterTitle: self.youtubePlayer.chapters.last { $0.startTime <= time }?.title
                )
                .fixedSize()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { self.previewCardSize = $0 }
                .position(x: centerX, y: -(self.previewCardSize.height / 2) - 16)
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.12), value: self.previewFraction != nil)
    }

    private var progressTextValue: TimeInterval {
        self.isSeeking ? self.seekValue * self.youtubePlayer.duration : self.displayedPlaybackProgress
    }

    private var displayedPlaybackProgress: TimeInterval {
        self.seekHold.displayProgress(observedProgress: self.youtubePlayer.progress)
    }

    private var currentSeekIdentity: String {
        self.youtubePlayer.currentVideo?.videoId ?? "none"
    }

    private func performSeek() {
        guard self.isSeeking, self.canSeek else { return }
        let seekTime = self.seekValue * self.youtubePlayer.duration
        let holdID = self.seekHold.begin(target: seekTime)
        self.isSeeking = false
        self.youtubePlayer.seek(to: seekTime)

        Task { @MainActor in
            try? await Task.sleep(for: PlayerBarSeekHold.timeout)
            if self.seekHold.clearIfCurrent(holdID) {
                self.syncSeekValueFromDisplayedProgress()
            }
        }
    }

    /// Writes the hold back only when reconciling changes it, so idle ticks don't invalidate the lane twice.
    private func reconcileHold(observedProgress: TimeInterval) {
        var hold = self.seekHold
        hold.reconcile(observedProgress: observedProgress)
        if hold != self.seekHold {
            self.seekHold = hold
        }
    }

    private func clearSeekHold() {
        self.seekHold.clear()
        self.isSeeking = false
        self.syncSeekValueFromDisplayedProgress()
    }

    private func syncSeekValueFromDisplayedProgress() {
        if self.youtubePlayer.duration > 0 {
            self.seekValue = self.displayedPlaybackProgress / self.youtubePlayer.duration
        } else {
            self.seekValue = 0
        }
    }
}
