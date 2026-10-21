#if DEBUG
    import Foundation
    import SwiftUI
    import Testing
    @testable import Kaset

    @MainActor
    struct DebugSessionRestoreTests {
        @Test("Only an explicit opt-in environment restores the last page")
        func requiresExplicitOptIn() {
            #expect(DebugSessionRestore.isRequested(environment: [:]) == false)
            #expect(DebugSessionRestore.isRequested(environment: ["KASET_RESTORE_LAST_PAGE": "0"]) == false)
            #expect(DebugSessionRestore.isRequested(environment: ["KASET_RESTORE_LAST_PAGE": "1"]))
        }

        @Test("A YouTube navigation path survives an encode/decode round trip")
        func youtubePathRoundTrips() throws {
            let video = MockYouTubeClient.makeVideo(videoId: "abc", title: "A video")
            var path = NavigationPath()
            path.append(YouTubeRoute.channel(channelId: "UC123"))
            path.append(YouTubeRoute.watch(video))

            let data = try JSONEncoder().encode(#require(path.codable))
            let restored = try NavigationPath(JSONDecoder().decode(NavigationPath.CodableRepresentation.self, from: data))

            #expect(restored.count == 2)
            #expect(try JSONEncoder().encode(#require(restored.codable)) == data)
        }

        @Test("A snapshot keeps the current video and its position")
        func snapshotRoundTripsPlayback() throws {
            let video = MockYouTubeClient.makeVideo(videoId: "abc", title: "A video")
            let snapshot = DebugSessionRestore.Snapshot(
                musicSelection: nil,
                youtubeSelection: "Home",
                playback: .init(video: video, progress: 123.5, isFloating: true),
                youtubePath: nil
            )

            let restored = try JSONDecoder().decode(
                DebugSessionRestore.Snapshot.self,
                from: JSONEncoder().encode(snapshot)
            )

            #expect(restored == snapshot)
            #expect(restored.playback?.video.videoId == "abc")
            #expect(restored.playback?.progress == 123.5)
        }

        @Test("Nothing is restored for a launch that did not ask for it")
        func noPlaybackWithoutOptIn() {
            #expect(DebugSessionRestore.defersStart == false)
        }
    }
#endif
