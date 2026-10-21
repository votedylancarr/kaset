#if DEBUG
    import Foundation
    import SwiftUI

    // MARK: - DebugSessionRestore

    /// Debug-build-only: remembers the page you were on so the edit → rebuild →
    /// relaunch loop (`Scripts/compile_and_run.sh`) lands back where you were.
    ///
    /// Restoring is opt-in per launch: only a process started with
    /// `KASET_RESTORE_LAST_PAGE=1` in its environment (which `compile_and_run.sh`
    /// sets) reads the saved page. A normal launch — double-click, Dock, the
    /// installed release app — never restores, and none of this exists in
    /// release builds.
    @MainActor
    enum DebugSessionRestore {
        nonisolated static let environmentKey = "KASET_RESTORE_LAST_PAGE"
        private static let defaultsKey = "debug.lastPageSnapshot"

        /// Whether this launch asked to restore the previous debug session.
        static var isRequestedAtLaunch: Bool {
            self.isRequested(environment: ProcessInfo.processInfo.environment)
        }

        nonisolated static func isRequested(environment: [String: String]) -> Bool {
            environment[self.environmentKey] == "1"
        }

        /// The YouTube video that was loaded and where it was.
        struct Playback: Codable, Equatable {
            var video: YouTubeVideo
            var progress: Double
            /// Whether the video was in the floating window (no watch page open for it).
            var isFloating: Bool
        }

        struct Snapshot: Codable, Equatable {
            var musicSelection: String?
            var youtubeSelection: String?
            var playback: Playback?
            /// JSON of `NavigationPath.CodableRepresentation`; `nil` when the path
            /// is empty or holds a value that isn't `Codable`.
            var youtubePath: Data?
        }

        // MARK: Saving

        static func save(
            musicSelection: NavigationItem?,
            youtubeSelection: YouTubeNavigationItem?,
            youtubePath: NavigationPath,
            playback: Playback?
        ) {
            let pathData = youtubePath.isEmpty ? nil : youtubePath.codable.flatMap { try? JSONEncoder().encode($0) }
            let snapshot = Snapshot(
                musicSelection: musicSelection?.rawValue,
                youtubeSelection: youtubeSelection?.rawValue,
                // Until the restored video has been brought back, keep saving it, so a
                // quick second relaunch doesn't lose it to the not-yet-playing state.
                playback: playback ?? self.pendingPlayback,
                youtubePath: pathData
            )
            guard let data = try? JSONEncoder().encode(snapshot),
                  data != UserDefaults.standard.data(forKey: self.defaultsKey)
            else { return }
            UserDefaults.standard.set(data, forKey: self.defaultsKey)
        }

        // MARK: Restoring

        /// The saved page, read once at launch (the save loop overwrites the stored
        /// copy within a second) and only when this launch asked to restore.
        private static let launchSnapshot: Snapshot? = {
            guard DebugSessionRestore.isRequestedAtLaunch,
                  let data = UserDefaults.standard.data(forKey: DebugSessionRestore.defaultsKey)
            else { return nil }
            return try? JSONDecoder().decode(Snapshot.self, from: data)
        }()

        private static func loadIfRequested() -> Snapshot? {
            self.launchSnapshot
        }

        /// The restored video, until it has been started again.
        private static var pendingPlayback: Playback? = launchSnapshot?.playback

        /// How long after launch a restore may still hold back playback.
        private static let restoreWindow: TimeInterval = 10
        private static let launchDate = Date()

        /// Whether watch pages should hold their own playback: a saved video is about to
        /// be started in one place, after the account check, so pages restored in the
        /// navigation stack must not each start a video (and then reload it when the
        /// account check finishes).
        static var defersStart: Bool {
            self.pendingPlayback != nil && Date().timeIntervalSince(self.launchDate) < self.restoreWindow
        }

        /// Starts the saved video once, from where it was, after the account check has
        /// finished (or the restore window passes), then pops it out again if it was floating.
        static func startRestoredPlayback(
            into player: YouTubePlayerService,
            isAccountVerified: @MainActor () -> Bool
        ) async {
            guard self.pendingPlayback != nil else { return }
            while !isAccountVerified(), self.defersStart {
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard let pending = self.pendingPlayback else { return }
            self.pendingPlayback = nil
            guard player.currentVideo == nil else { return }
            player.play(video: pending.video, startAt: pending.progress >= 3 ? pending.progress : nil)
            if pending.isFloating {
                player.popOutToWindow()
            } else {
                player.activeInlineVideoId = pending.video.videoId
            }
        }

        static func restoredMusicSelection() -> NavigationItem? {
            self.loadIfRequested()?.musicSelection.flatMap(NavigationItem.init(rawValue:))
        }

        static func restoredYouTubeSelection() -> YouTubeNavigationItem? {
            self.loadIfRequested()?.youtubeSelection.flatMap(YouTubeNavigationItem.init(rawValue:))
        }

        static func restoredYouTubePath() -> NavigationPath? {
            guard let data = self.loadIfRequested()?.youtubePath,
                  let representation = try? JSONDecoder().decode(NavigationPath.CodableRepresentation.self, from: data)
            else { return nil }
            return NavigationPath(representation)
        }
    }
#else
    import SwiftUI

    /// Release builds never restore a debug session.
    @MainActor
    enum DebugSessionRestore {
        static func restoredMusicSelection() -> NavigationItem? {
            nil
        }

        static func restoredYouTubeSelection() -> YouTubeNavigationItem? {
            nil
        }

        static func restoredYouTubePath() -> NavigationPath? {
            nil
        }

        static var defersStart: Bool {
            false
        }
    }
#endif
