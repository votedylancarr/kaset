import Observation
import SwiftUI

// MARK: - AmbientGlowState

/// Where the YouTube watch page wants its ambient halo drawn. The watch view
/// publishes its video frame (in the main window's named space) plus the
/// glow's inputs; `AmbientGlowHost` renders the halo behind the whole window
/// content, so it can reach under the sidebar and the toolbar instead of being
/// clipped to the scrolling page.
@MainActor
@Observable
final class AmbientGlowState {
    static let shared = AmbientGlowState()

    struct Anchor: Equatable {
        var frame: CGRect
        var videoId: String?
        var thumbnailURL: URL?
        var style: AmbientBackdropStyle
        var liveFraction: Double?
        var storyboardSpec: String?
        var strength: Double
    }

    var anchor: Anchor?

    private init() {}
}

// MARK: - AmbientGlowSpace

enum AmbientGlowSpace {
    /// Named coordinate space attached to the main window's split view.
    static let name = "kasetMainContent"
}

// MARK: - AmbientGlowHost

/// Draws the halo for the current `AmbientGlowState.anchor`, if any. Place it as
/// a background of the view that carries `AmbientGlowSpace.name`.
struct AmbientGlowHost: View {
    /// How far the halo extends past the video frame on every side.
    private static let spread: CGFloat = 160

    private var state = AmbientGlowState.shared

    var body: some View {
        GeometryReader { geometry in
            // Positions are published in the named space; this view may extend
            // past it (under the toolbar), so convert through its own origin.
            let origin = geometry.frame(in: .named(AmbientGlowSpace.name)).origin
            if let anchor = self.state.anchor, anchor.style != .off, anchor.frame.width > 0 {
                let width = anchor.frame.width + Self.spread * 2
                let height = anchor.frame.height + Self.spread * 2
                AmbientVideoBackdrop(
                    videoId: anchor.videoId,
                    thumbnailURL: anchor.thumbnailURL,
                    style: anchor.style,
                    liveFraction: anchor.liveFraction,
                    storyboardSpec: anchor.storyboardSpec,
                    anchoredToVideo: true,
                    strength: anchor.strength,
                    haloInset: Self.spread
                )
                .frame(width: width, height: height)
                .position(
                    x: anchor.frame.midX - origin.x,
                    y: anchor.frame.midY - origin.y
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
