import SwiftUI

// MARK: - YouTubePopOutCover

/// Covers a freshly opened pop-out with the video's thumbnail for its first moments,
/// then fades it out to the live video. Moving the web view into a new window makes its
/// video layers re-tile and re-place for about a second, which shows as a video that
/// jumps size; the still frame at the right size hides that settling.
struct YouTubePopOutCover: View {
    /// How long the thumbnail stays before fading away.
    nonisolated static let duration: Duration = .milliseconds(1300)

    let video: YouTubeVideo?

    @State private var isCovering = true

    var body: some View {
        ZStack {
            if self.isCovering, let video {
                ZStack {
                    Color.black
                    CachedAsyncImage(
                        url: video.thumbnailURL,
                        targetSize: CGSize(width: 1280, height: 720)
                    ) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.black
                    }
                }
                .clipped()
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(for: Self.duration)
            withAnimation(.easeOut(duration: 0.35)) {
                self.isCovering = false
            }
        }
    }
}
