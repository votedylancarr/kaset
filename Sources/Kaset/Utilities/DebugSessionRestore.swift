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

        struct Snapshot: Codable, Equatable {
            var musicSelection: String?
            var youtubeSelection: String?
            /// JSON of `NavigationPath.CodableRepresentation`; `nil` when the path
            /// is empty or holds a value that isn't `Codable`.
            var youtubePath: Data?
        }

        // MARK: Saving

        static func save(
            musicSelection: NavigationItem?,
            youtubeSelection: YouTubeNavigationItem?,
            youtubePath: NavigationPath
        ) {
            let pathData = youtubePath.isEmpty ? nil : youtubePath.codable.flatMap { try? JSONEncoder().encode($0) }
            let snapshot = Snapshot(
                musicSelection: musicSelection?.rawValue,
                youtubeSelection: youtubeSelection?.rawValue,
                youtubePath: pathData
            )
            guard let data = try? JSONEncoder().encode(snapshot),
                  data != UserDefaults.standard.data(forKey: self.defaultsKey)
            else { return }
            UserDefaults.standard.set(data, forKey: self.defaultsKey)
        }

        // MARK: Restoring

        private static func loadIfRequested() -> Snapshot? {
            guard self.isRequestedAtLaunch,
                  let data = UserDefaults.standard.data(forKey: self.defaultsKey)
            else { return nil }
            return try? JSONDecoder().decode(Snapshot.self, from: data)
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
    }
#endif
