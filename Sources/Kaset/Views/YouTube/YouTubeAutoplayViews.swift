import SwiftUI

// MARK: - YouTubeRelatedHeader

/// "Related" section header with the Autoplay switch, like YouTube's "Up next".
struct YouTubeRelatedHeader: View {
    @State private var settings = SettingsManager.shared

    var body: some View {
        HStack(spacing: 8) {
            Text("Related", comment: "Related videos section header")
                .font(.title3.bold())
            Spacer(minLength: 8)
            Toggle(isOn: self.$settings.autoplayNextVideo) {
                Text("Autoplay", comment: "Toggle: play the next suggested video automatically")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help(String(localized: "Play the next suggested video automatically when this one ends"))
            .accessibilityIdentifier(AccessibilityID.YouTubeContent.autoplayToggle)
        }
    }
}

// MARK: - YouTubeVideoOverlays

/// Overlays drawn on top of the video surface: the thumbnail cover that fades
/// out as a new video starts, and the "Up Next" card while autoplay counts down.
struct YouTubeVideoOverlays: View {
    @Environment(YouTubePlayerService.self) private var youtubePlayer

    /// The video this surface presents, or `nil` when none.
    let video: YouTubeVideo?
    /// Which surface this overlay sits on; it only draws while the player's
    /// surface lives there.
    let location: YouTubePlayerService.SurfaceLocation

    private var isCurrent: Bool {
        self.video != nil
            && self.youtubePlayer.currentVideo?.videoId == self.video?.videoId
            && self.youtubePlayer.surfaceLocation == self.location
    }

    private var showsCover: Bool {
        self.isCurrent && self.youtubePlayer.isPlaybackLoading
    }

    private var countdown: YouTubePlayerService.AutoplayCountdown? {
        guard self.isCurrent,
              let countdown = self.youtubePlayer.autoplayCountdown,
              countdown.afterVideoId == self.video?.videoId
        else { return nil }
        return countdown
    }

    var body: some View {
        ZStack {
            if self.showsCover, let video {
                CachedAsyncImage(
                    url: video.thumbnailURL,
                    targetSize: CGSize(width: 1280, height: 720)
                ) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.black)
                }
                .overlay(.black.opacity(0.25))
                .clipped()
                .transition(.opacity)
                .allowsHitTesting(false)
            }

            if let countdown = self.countdown {
                YouTubeAutoplayCountdownCard(countdown: countdown)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeInOut(duration: 0.45), value: self.showsCover)
        .animation(.smooth(duration: 0.4), value: self.countdown)
    }
}

// MARK: - YouTubeAutoplayCountdownCard

/// "Up Next" card shown over the ended video: the next video's thumbnail, a
/// ring counting down, and Cancel / Play Now.
struct YouTubeAutoplayCountdownCard: View {
    @Environment(YouTubePlayerService.self) private var youtubePlayer

    let countdown: YouTubePlayerService.AutoplayCountdown

    var body: some View {
        ZStack {
            CachedAsyncImage(
                url: self.countdown.video.thumbnailURL,
                targetSize: CGSize(width: 640, height: 360)
            ) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(.black)
            }
            .blur(radius: 24)
            .overlay(.black.opacity(0.62))
            .clipped()

            VStack(spacing: 14) {
                self.ring

                VStack(spacing: 4) {
                    Text("Up Next", comment: "Autoplay card heading")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(self.countdown.video.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    if let channel = self.countdown.video.channelName {
                        Text(channel)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        self.youtubePlayer.cancelAutoplayCountdown()
                    } label: {
                        Text("Cancel", comment: "Cancel autoplay")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 10)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        self.youtubePlayer.playAutoplayCandidateNow()
                    } label: {
                        Text("Play Now", comment: "Start the next video immediately")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                }
                .controlSize(.large)
            }
            .padding(24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.YouTubeContent.autoplayCountdownCard)
    }

    /// Circular countdown; progress is derived from the start date so the ring
    /// animates smoothly without per-tick state changes.
    private var ring: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(self.countdown.startedAt)
            let remaining = max(0, self.countdown.duration - elapsed)
            let progress = min(max(elapsed / self.countdown.duration, 0), 1)
            ZStack {
                Circle().stroke(.white.opacity(0.2), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: 1 - progress)
                    .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(remaining.rounded(.up)))")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)
        }
    }
}

// MARK: - AccessibilityID Additions

extension AccessibilityID.YouTubeContent {
    static let autoplayToggle = "youtubeContent.autoplayToggle"
    static let autoplayCountdownCard = "youtubeContent.autoplayCountdownCard"
}
