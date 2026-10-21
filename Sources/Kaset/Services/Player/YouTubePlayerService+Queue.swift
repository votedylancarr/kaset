import Foundation
import SwiftUI

// MARK: - YouTube queue

extension YouTubePlayerService {
    /// What plays next: the first queued video, else the first related video.
    var nextVideoCandidate: YouTubeVideo? {
        self.userQueue.first ?? self.upNext.first
    }

    /// Whether `video` can be queued (Shorts have their own player and are skipped).
    func canQueue(_ video: YouTubeVideo) -> Bool {
        !video.isShort
    }

    func isQueued(_ video: YouTubeVideo) -> Bool {
        self.userQueue.contains { $0.videoId == video.videoId }
    }

    /// Adds a video to the end of the queue. Already-queued or currently playing
    /// videos are left alone.
    func addToQueue(_ video: YouTubeVideo) {
        guard self.canQueue(video),
              !self.isQueued(video),
              video.videoId != self.currentVideo?.videoId
        else { return }
        self.userQueue.append(video)
    }

    /// Puts a video at the front of the queue, moving it there if already queued.
    func playNext(_ video: YouTubeVideo) {
        guard self.canQueue(video), video.videoId != self.currentVideo?.videoId else { return }
        self.userQueue.removeAll { $0.videoId == video.videoId }
        self.userQueue.insert(video, at: 0)
    }

    func removeFromQueue(_ video: YouTubeVideo) {
        self.userQueue.removeAll { $0.videoId == video.videoId }
    }

    func moveInQueue(fromOffsets source: IndexSet, toOffset destination: Int) {
        self.userQueue.move(fromOffsets: source, toOffset: destination)
    }

    func clearQueue() {
        self.userQueue.removeAll()
    }

    /// Plays a queued video now. It leaves the queue; the rest keeps its order.
    func playQueuedVideo(_ video: YouTubeVideo) {
        guard self.isQueued(video) else { return }
        if let current = self.currentVideo {
            self.advance(to: video, replacingWatchPage: self.activeInlineVideoId == current.videoId)
        } else {
            self.removeFromQueue(video)
            self.play(video: video)
        }
    }
}
