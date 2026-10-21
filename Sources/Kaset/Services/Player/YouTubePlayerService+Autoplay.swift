import Foundation

// MARK: - AutoplayCountdown

extension YouTubePlayerService {
    /// The next video queued by autoplay and when its countdown began.
    struct AutoplayCountdown: Equatable {
        let afterVideoId: String
        let video: YouTubeVideo
        let startedAt: Date
        let duration: TimeInterval
    }

    /// Seconds the "Up Next" card counts down before the next video starts.
    nonisolated static let autoplayCountdownDuration: TimeInterval = 3

    // MARK: - Autoplay

    /// Called when the current video finishes. If autoplay is on, resolves the
    /// next suggested video and starts the countdown; the next video then
    /// starts unless the user cancels or does anything else first.
    func beginAutoplayCountdownIfEnabled() {
        guard self.shouldAutoplayNext(),
              let current = self.currentVideo,
              !current.isShort, !current.isLive,
              self.surfaceLocation != .none
        else { return }

        self.cancelAutoplayCountdown()
        let generation = self.autoplayGeneration
        self.autoplayTask = Task { [weak self] in
            guard let self,
                  let next = await self.resolveAutoplayCandidate(after: current, generation: generation)
            else { return }
            let countdown = AutoplayCountdown(
                afterVideoId: current.videoId,
                video: next,
                startedAt: Date(),
                duration: Self.autoplayCountdownDuration
            )
            self.autoplayCountdown = countdown
            do {
                try await Task.sleep(for: .seconds(countdown.duration))
            } catch {
                return
            }
            guard generation == self.autoplayGeneration,
                  self.autoplayCountdown == countdown,
                  self.currentVideo?.videoId == current.videoId
            else { return }
            // Something queued while the card counted down goes first.
            self.advance(to: self.userQueue.first ?? next, replacingWatchPage: self.activeInlineVideoId == current.videoId)
        }
    }

    /// Stops a pending autoplay and hides the "Up Next" card.
    func cancelAutoplayCountdown() {
        self.autoplayGeneration &+= 1
        self.autoplayTask?.cancel()
        self.autoplayTask = nil
        if self.autoplayCountdown != nil {
            self.autoplayCountdown = nil
        }
    }

    /// Skips the rest of the countdown and starts the queued video now.
    func playAutoplayCandidateNow() {
        guard let countdown = self.autoplayCountdown,
              self.currentVideo?.videoId == countdown.afterVideoId
        else { return }
        self.advance(to: countdown.video, replacingWatchPage: self.activeInlineVideoId == countdown.afterVideoId)
    }

    private func resolveAutoplayCandidate(
        after current: YouTubeVideo,
        generation: UInt64
    ) async -> YouTubeVideo? {
        if let queued = self.nextVideoCandidate {
            return queued
        }
        guard let client = self.youtubeClient else { return nil }
        let fetched = await (try? client.getWatchNext(videoId: current.videoId))?
            .related.first { !$0.isShort }
        guard generation == self.autoplayGeneration,
              self.currentVideo?.videoId == current.videoId
        else { return nil }
        return fetched
    }
}
