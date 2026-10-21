import AppKit
import CoreGraphics
import SwiftUI

// MARK: - AmbientVideoBackdrop

/// PROTOTYPE — "live ambient" glow for the YouTube watch page.
///
/// We cannot sample the playing video's pixels (Widevine DRM black-frames every
/// capture path, and the surface is an opaque AppKit web view). Instead this
/// renders the effect itself: a drifting "aurora" of luminous color blobs pulled
/// from the video thumbnail — and, in `.live` mode, crossfading through the
/// colors of YouTube's non-DRM storyboard sprite-sheet cells keyed to playback
/// progress, so the color shifts as the video plays without ever touching a
/// protected frame. The page's existing Liquid Glass chrome tints over it as a
/// bonus, but the glow stands on its own.
///
/// Self-contained on purpose: it does NOT edit the shared `AccentBackground`
/// (used by the artist/playlist/podcast pages). `AmbientGlowHost` draws it
/// behind the main window; `YouTubeWatchView` publishes where.
struct AmbientVideoBackdrop: View {
    // MARK: Inputs

    let videoId: String?
    let thumbnailURL: URL?
    let style: AmbientBackdropStyle
    /// 0…1 playback position for `.live` crossfade; `nil` when this video is
    /// not the one actively playing (the parent guards `duration > 0`).
    var liveFraction: Double?
    /// YouTube storyboard spec for fine-grained `.live` color. When present,
    /// its sprite-sheet cells replace the coarse 3-still source. `nil` until the
    /// player publishes it (or unavailable).
    var storyboardSpec: String?
    /// When true the glow is a soft halo meant to sit behind the video frame
    /// (blobs hug the frame's edges, no window-wide base fill, edges fade out)
    /// instead of a full-window background.
    var anchoredToVideo = false
    /// User-chosen multiplier on the anchored halo's brightness (1 = default).
    var strength = 1.0
    /// How far the anchored halo's frame extends past the video on each side.
    /// The blobs are placed on the video's edges using this.
    var haloInset: CGFloat = 160

    // MARK: State

    @State private var palette: ColorExtractor.ColorPalette = .default
    /// Distinct vivid colors from the thumbnail (used by `.glow` and as the
    /// `.live` fallback when storyboard frames are unavailable).
    @State private var thumbnailSwatches: [Color] = []
    /// Per-storyboard-frame swatch sets for the `.live` crossfade.
    @State private var frameSwatches: [[Color]] = []
    /// The `videoId` the published colors belong to. The render path ignores
    /// any state whose tag doesn't match the current `videoId`, so a previous
    /// video's colors can never show through while a new load is in flight —
    /// regardless of how the async fetches interleave.
    @State private var loadedVideoId: String?
    @State private var lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Slow ambient drift does not need display-link cadence. Eight samples per
    /// second keeps the large blurred blobs moving smoothly enough while cutting
    /// steady-state invalidations substantially compared with `.animation`.
    nonisolated static let animatedTimelineInterval: TimeInterval = 1.0 / 8.0

    // MARK: Body

    var body: some View {
        let style = self.effectiveStyle
        Group {
            if style == .off {
                Color.clear
            } else if self.reduceTransparency {
                // Reduce Transparency: flatten to a near-solid low tint, no glow.
                if self.anchoredToVideo {
                    Color.clear
                } else {
                    self.flatTint
                }
            } else if self.anchoredToVideo {
                self.ambientContent
                    .mask(self.haloMask)
            } else {
                ZStack {
                    Color.kasetBackground
                    self.ambientContent
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: self.palette)
        .animation(.easeInOut(duration: 0.5), value: style)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange)) { _ in
            self.lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .task(id: self.loadKey) {
            await self.load()
        }
    }

    /// Re-runs the loader when the video, style, or storyboard availability
    /// changes (the spec arrives a beat after playback starts).
    private var loadKey: String {
        let style = self.effectiveStyle
        let hasStoryboardSpec = style == .live && self.storyboardSpec != nil
        return "\(self.videoId ?? "-")|\(style.rawValue)|\(hasStoryboardSpec)"
    }

    /// Style actually rendered after energy/accessibility downgrades. `.live`
    /// is the only style that fetches storyboard sheets and continuously
    /// cross-fades with playback; under Low Power Mode or Reduce Motion, prefer
    /// the static thumbnail-derived `.soft` glow instead.
    private var effectiveStyle: AmbientBackdropStyle {
        Self.effectiveStyle(
            requestedStyle: self.style,
            reduceMotion: self.reduceMotion,
            lowPowerModeEnabled: self.lowPowerModeEnabled
        )
    }

    nonisolated static func effectiveStyle(
        requestedStyle style: AmbientBackdropStyle,
        reduceMotion: Bool,
        lowPowerModeEnabled: Bool
    ) -> AmbientBackdropStyle {
        if style == .live, reduceMotion || lowPowerModeEnabled {
            return .soft
        }
        return style
    }

    // MARK: Ambient composition

    /// Branch on Reduce Motion rather than pausing the `TimelineView`, mirroring
    /// the repo's `PulseModifier` pattern. `.soft` is intentionally steady (no
    /// drift) so it reads as a calm version of the same glow.
    private var ambientContent: some View {
        GeometryReader { geo in
            let style = self.effectiveStyle
            if style == .soft || self.reduceMotion {
                self.auroraLayer(size: geo.size, time: nil)
            } else {
                TimelineView(.periodic(from: .now, by: Self.animatedTimelineInterval)) { timeline in
                    self.auroraLayer(
                        size: geo.size,
                        time: timeline.date.timeIntervalSinceReferenceDate
                    )
                }
            }
        }
    }

    /// The hero: one drifting aurora, or two crossfading by playback position in
    /// `.live` mode. Both sub-layers keep orbiting so motion never stops.
    @ViewBuilder
    private func auroraLayer(size: CGSize, time: TimeInterval?) -> some View {
        let frames = self.renderFrames
        // `.soft` is the calm style: same colors, dimmer than the drifting glow.
        let baseIntensity: Double = self.effectiveStyle == .soft ? 0.7 : 1.0
        // The anchored halo is a subtle accent, not a page wash.
        let intensity = self.anchoredToVideo ? baseIntensity * Self.haloIntensityScale * self.strength : baseIntensity
        // Under Reduce Motion, collapse `.live` to a single static frame: the
        // blobs already stop drifting (time: nil) and the colors must not
        // cross-fade as playback advances either.
        if frames.count <= 1 || self.reduceMotion {
            Self.aurora(
                colors: frames.first ?? self.fallbackColors,
                size: size,
                time: time,
                colorScheme: self.colorScheme,
                intensity: intensity,
                anchored: self.anchoredToVideo,
                inset: self.haloInset
            )
        } else {
            let position = (self.liveFraction ?? 0) * Double(frames.count - 1)
            let lower = min(max(Int(position.rounded(.down)), 0), frames.count - 1)
            let upper = min(lower + 1, frames.count - 1)
            let blend = position - Double(lower)
            let lowerColors = frames[lower].isEmpty ? self.fallbackColors : frames[lower]
            let upperColors = frames[upper].isEmpty ? self.fallbackColors : frames[upper]
            ZStack {
                Self.aurora(colors: lowerColors, size: size, time: time, colorScheme: self.colorScheme, intensity: intensity, anchored: self.anchoredToVideo, inset: self.haloInset)
                    .opacity(1 - blend)
                Self.aurora(colors: upperColors, size: size, time: time, colorScheme: self.colorScheme, intensity: intensity, anchored: self.anchoredToVideo, inset: self.haloInset)
                    .opacity(blend)
            }
            .animation(.easeInOut(duration: 0.7), value: self.liveFraction)
        }
    }

    /// Whether the published color state belongs to the current video. Stale
    /// state (from a prior video, mid-transition) is treated as not-yet-loaded.
    private var colorsAreCurrent: Bool {
        self.loadedVideoId == self.videoId
    }

    /// The palette to render: the loaded one only when it belongs to the current
    /// video, otherwise the neutral default. Every palette read goes through
    /// this so no render path can show a prior video's colors mid-transition.
    private var currentPalette: ColorExtractor.ColorPalette {
        self.colorsAreCurrent ? self.palette : .default
    }

    /// The swatch set(s) feeding the aurora for the current style.
    private var renderFrames: [[Color]] {
        switch self.effectiveStyle {
        case .live where self.colorsAreCurrent && !self.frameSwatches.isEmpty:
            self.frameSwatches
        default:
            [self.fallbackColors]
        }
    }

    /// Thumbnail swatches, or palette-derived colors if extraction found none.
    /// Falls back to the neutral default palette until the current video's
    /// colors have actually loaded.
    private var fallbackColors: [Color] {
        if self.colorsAreCurrent, !self.thumbnailSwatches.isEmpty {
            return self.thumbnailSwatches
        }
        return [self.currentPalette.primary, self.currentPalette.secondary]
    }

    /// A single drifting field of additively-blended color blobs. Static when
    /// `time` is nil (Reduce Motion or the `.soft` style). `intensity` scales
    /// the overall brightness so `.soft` reads dimmer than the drifting glow.
    private static func aurora(
        colors: [Color],
        size: CGSize,
        time: TimeInterval?,
        colorScheme: ColorScheme,
        intensity: Double,
        anchored: Bool = false,
        inset: CGFloat = 0
    ) -> some View {
        let isDark = colorScheme == .dark
        // Additive light reads as "glow" on a dark base; on a light base it
        // blows out to white, so fall back to a softer source-over tint.
        let blend: BlendMode = isDark ? .plusLighter : .normal
        let coreOpacity: Double = (isDark ? 0.55 : 0.30) * intensity
        let elapsed = time ?? 0
        // Anchored: blobs sit ON the video's edges (the video hides their inner
        // half), so the light that spills out matches what's at each edge.
        let frameWidth = size.width - inset * 2
        let frameHeight = size.height - inset * 2
        let layout: [CGPoint] = anchored
            ? Self.haloLayout.map { CGPoint(x: inset + $0.x * frameWidth, y: inset + $0.y * frameHeight) }
            : Self.layout.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        let blurRadius: CGFloat = anchored ? 60 : 46
        let driftScale: CGFloat = anchored ? 0.5 : 1.0

        return ZStack {
            ForEach(Array(colors.prefix(layout.count).enumerated()), id: \.offset) { index, color in
                let spot = layout[index]
                let period = Self.periods[index]
                let phase = Self.phases[index]
                let driftX = time == nil ? 0 : 0.12 * driftScale * size.width * sin(elapsed / period + phase)
                let driftY = time == nil ? 0 : 0.10 * driftScale * size.height * cos(elapsed / (period + 6) + phase)
                let diameter = anchored ? frameHeight * 0.85 : size.width

                RadialGradient(
                    colors: [color.opacity(coreOpacity), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter * 0.5
                )
                .frame(width: diameter, height: diameter)
                .position(
                    x: spot.x + driftX,
                    y: spot.y + driftY
                )
                .blendMode(blend)
            }
        }
        .compositingGroup()
        .blur(radius: blurRadius)
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// Resting positions (unit coords) for up to five blobs — spread across the
    /// upper-mid field with one low so color still reaches the player bar.
    private static let layout: [(x: CGFloat, y: CGFloat)] = [
        (0.28, 0.24), (0.74, 0.20), (0.18, 0.58), (0.82, 0.64), (0.50, 0.42),
    ]

    /// Resting positions for the anchored halo, in unit coords of the video frame
    /// itself: upper/lower left edge, upper/lower right edge, and bottom center.
    /// Edge colors are sampled from the matching regions of the thumbnail.
    private static let haloLayout: [(x: CGFloat, y: CGFloat)] = [
        (0.0, 0.28), (1.0, 0.30), (0.0, 0.74), (1.0, 0.72), (0.5, 1.0),
    ]

    /// How much dimmer the anchored halo is than the full-window backdrop.
    private static let haloIntensityScale: Double = 0.9

    /// Fades the halo to nothing at the edge of its (padded) frame, so it never
    /// ends in a hard line against the plain window background. Solid well inside
    /// the border, with a wide soft falloff outward.
    private var haloMask: some View {
        let inset = self.haloInset * 0.45
        return Rectangle()
            .fill(.black)
            .padding(inset)
            .blur(radius: inset * 0.8)
    }

    /// Mutually-prime orbit periods (seconds) so the drift never visibly loops.
    private static let periods: [Double] = [19, 23, 29, 31, 37]
    private static let phases: [Double] = [0.0, 1.7, 3.1, 4.6, 5.9]

    /// Reduce Transparency fallback: a flat, low-opacity tint, no motion.
    private var flatTint: some View {
        ZStack {
            Color.kasetBackground
            LinearGradient(
                colors: [self.currentPalette.primary.opacity(0.14), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
    }

    // MARK: Loading

    private func load() async {
        let style = self.effectiveStyle
        guard style != .off else { return }

        // Resolve thumbnail colors, then publish — assigning defaults on
        // failure too, so a new video whose thumbnail is missing/fails can't
        // keep showing the previous video's colors (e.g. after SPA drift, when
        // this view instance is reused). Guarded by cancellation so a superseded
        // load never clobbers the current one.
        let resolved: (palette: ColorExtractor.ColorPalette, swatches: [Color])? = if let url = self.thumbnailURL ?? self.fallbackThumbnailURL {
            // Same URL + size the watch poster already fetches → warm cache hit,
            // no second network download.
            await Self.loadPaletteAndSwatches(url: url, size: CGSize(width: 1280, height: 720))
        } else {
            nil
        }
        if Task.isCancelled {
            return
        }
        let isNewVideo = self.loadedVideoId != self.videoId
        self.palette = resolved?.palette ?? .default
        self.thumbnailSwatches = resolved?.swatches ?? []
        // Drop the prior video's storyboard frames so `.live` falls back to the
        // (current) thumbnail colors until fresh frames load, rather than
        // briefly crossfading the old video's frames.
        if isNewVideo {
            self.frameSwatches = []
        }
        // Tag the published colors with this video. Until this runs for the
        // current `videoId`, the render path shows the neutral default rather
        // than a prior video's colors.
        self.loadedVideoId = self.videoId

        guard style == .live else {
            self.frameSwatches = []
            return
        }

        // Prefer the storyboard sprite sheet (dozens of timeline cells from a
        // single fetch) for moment-to-moment color; fall back to the 3 sampled
        // stills when no spec is available (live streams, age-gated, etc.).
        if let spec = self.storyboardSpec,
           let sheet = StoryboardSheet(spec: spec),
           let sets = await Self.loadStoryboardSwatches(sheet: sheet),
           !sets.isEmpty
        {
            if Task.isCancelled {
                return
            }
            self.frameSwatches = sets
            return
        }

        var sets: [[Color]] = []
        for url in self.storyboardFrameURLs() {
            if let swatches = await Self.loadSwatches(url: url, size: CGSize(width: 320, height: 180)),
               !swatches.isEmpty
            {
                sets.append(swatches)
            }
        }
        if Task.isCancelled {
            return
        }
        self.frameSwatches = sets
    }

    /// `mqdefault.jpg` is the 16:9, no-letterbox thumbnail when the model has no
    /// `thumbnailURL`.
    private var fallbackThumbnailURL: URL? {
        guard let videoId else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(videoId)/mqdefault.jpg")
    }

    /// YouTube's three evenly-sampled storyboard stills (start/mid/end) — the
    /// `.live` fallback when no full storyboard spec is available.
    private func storyboardFrameURLs() -> [URL] {
        guard let videoId else { return [] }
        return (1 ... 3).compactMap { URL(string: "https://i.ytimg.com/vi/\(videoId)/\($0).jpg") }
    }

    // MARK: Off-main extraction

    //
    // `nonisolated` so the CPU-bound pixel work runs off the main actor and the
    // non-Sendable `NSImage` never escapes into MainActor state — only the
    // Sendable `[Color]` / `ColorPalette` cross back.

    // swiftformat:disable modifierOrder
    nonisolated private static func loadPaletteAndSwatches(
        url: URL,
        size: CGSize
    ) async -> (palette: ColorExtractor.ColorPalette, swatches: [Color])? {
        guard let nsImage = await ImageCache.shared.image(for: url, targetSize: size) else {
            return nil
        }
        return (ColorExtractor.extractPalette(from: nsImage), Self.extractSwatches(from: nsImage))
    }

    nonisolated private static func loadSwatches(url: URL, size: CGSize) async -> [Color]? {
        guard let nsImage = await ImageCache.shared.image(for: url, targetSize: size) else {
            return nil
        }
        return Self.extractSwatches(from: nsImage)
    }

    /// Fetches the storyboard sheet(s) and extracts one swatch set per cell, in
    /// timeline order, so the existing `liveFraction` crossfade walks them as
    /// the video plays. Dark cells (no vivid color) carry the previous cell's
    /// swatches forward so the glow never drops to black mid-timeline.
    nonisolated private static func loadStoryboardSwatches(sheet: StoryboardSheet) async -> [[Color]]? {
        var sets: [[Color]] = []
        var lastNonEmpty: [Color] = []
        for (sheetIndex, sheetURL) in sheet.sheetURLs.enumerated() {
            // Fetch at full size (nil) — downsampling a multi-cell sheet would
            // corrupt the per-cell crops.
            guard let nsImage = await ImageCache.shared.image(for: sheetURL, targetSize: nil),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else {
                continue
            }
            let rects = sheet.cellRects(
                forSheetAt: sheetIndex,
                pixelWidth: cgImage.width,
                height: cgImage.height
            )
            for rect in rects {
                guard let cell = cgImage.cropping(to: rect) else { continue }
                let swatches = Self.extractSwatches(from: NSImage(cgImage: cell, size: .zero))
                if !swatches.isEmpty {
                    lastNonEmpty = swatches
                }
                sets.append(lastNonEmpty)
            }
        }
        // Drop any leading empties (dark cells before the first vivid one) so
        // the crossfade starts on real color.
        let trimmed = sets.drop { $0.isEmpty }
        return trimmed.isEmpty ? nil : Array(trimmed)
    }

    /// Samples the image's edge regions, in the order of `haloLayout`: upper
    /// left, upper right, lower left, lower right, bottom center. Each is the
    /// region's average color, lifted just enough to read as emitted light, so the
    /// halo continues the colors found at the video's actual edges.
    nonisolated private static func extractSwatches(from image: NSImage) -> [Color] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }
        let dimension = 32
        guard let context = CGContext(
            data: nil,
            width: dimension,
            height: dimension,
            bitsPerComponent: 8,
            bytesPerRow: dimension * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), cgImage.width > 0, cgImage.height > 0 else {
            return []
        }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: dimension, height: dimension))
        guard let data = context.data else { return [] }
        let pointer = data.bindMemory(to: UInt8.self, capacity: dimension * dimension * 4)

        // Unit-coordinate rects (origin top-left, row 0 is the image's top).
        let regions: [CGRect] = [
            CGRect(x: 0.0, y: 0.08, width: 0.14, height: 0.42),
            CGRect(x: 0.86, y: 0.08, width: 0.14, height: 0.42),
            CGRect(x: 0.0, y: 0.50, width: 0.14, height: 0.42),
            CGRect(x: 0.86, y: 0.50, width: 0.14, height: 0.42),
            CGRect(x: 0.20, y: 0.86, width: 0.60, height: 0.14),
        ]
        let side = CGFloat(dimension)
        return regions.map { region in
            let firstColumn = Int(region.minX * side)
            let firstRow = Int(region.minY * side)
            let columns = firstColumn ..< max(Int(region.maxX * side), firstColumn + 1)
            let rows = firstRow ..< max(Int(region.maxY * side), firstRow + 1)
            var red = 0.0
            var green = 0.0
            var blue = 0.0
            var count = 0.0
            for row in rows where row < dimension {
                for column in columns where column < dimension {
                    let offset = (row * dimension + column) * 4
                    red += Double(pointer[offset])
                    green += Double(pointer[offset + 1])
                    blue += Double(pointer[offset + 2])
                    count += 1
                }
            }
            guard count > 0 else { return Color.clear }
            return Self.glowColor(red: red / count / 255, green: green / count / 255, blue: blue / count / 255)
        }
    }

    /// Lifts an edge color's brightness (so dim edges still glow) and slightly
    /// boosts saturation, keeping the hue faithful to the video.
    nonisolated private static func glowColor(red: Double, green: Double, blue: Double) -> Color {
        let base = NSColor(red: red, green: green, blue: blue, alpha: 1)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let lifted = NSColor(
            hue: hue,
            saturation: min(saturation * 1.15, 1),
            brightness: max(min(brightness * 1.25, 0.95), 0.35),
            alpha: 1
        )
        return Color(nsColor: lifted)
    }
    // swiftformat:enable modifierOrder
}

// MARK: - StoryboardSheet

/// Parses a YouTube storyboard spec string into fetchable sprite-sheet URLs and
/// per-cell crop rects. Format confirmed against yt-dlp / NewPipe and a live
/// video: `base|level0|level1|…`, where `base` is a URL template with `$L`/`$N`
/// placeholders and each level is `width#height#frameCount#cols#rows#interval#N#sigh`.
///
/// Prefers Level 0 (typically a single `default.jpg` of ~100 cells), so one HTTP
/// fetch yields dozens of evenly-spaced timeline samples — ideal for ambient
/// color. All grid values are parsed from the live spec, never hardcoded.
struct StoryboardSheet {
    let sheetURLs: [URL]
    private let cols: Int
    private let rows: Int
    let frameCount: Int
    /// Milliseconds between frames, or 0 when the frames are spread evenly over the
    /// whole video (YouTube's convention for the lowest level).
    let intervalMilliseconds: Int

    /// Sanity caps on values parsed from the (untrusted) WebView spec, so a
    /// malformed or hostile spec can't overflow the arithmetic or trigger a
    /// flood of image fetches. A real Level-0 sheet is ~10×10 = 100 cells in a
    /// single image; these ceilings sit comfortably above that and fail closed.
    private static let maxGridDimension = 50
    private static let maxFrameCount = 10000
    private static let maxSheets = 8

    /// Parses one storyboard level. Level 0 (the default) is the densest single sheet
    /// (one fetch, most cells), right for color sampling; hover previews use a larger
    /// level (`previewLevel(in:)`) and a higher `maxSheets`.
    init?(spec: String, level levelIndex: Int = 0, maxSheets: Int = StoryboardSheet.maxSheets) {
        let parts = spec.components(separatedBy: "|")
        guard levelIndex >= 0, parts.count >= levelIndex + 2 else { return nil }
        let base = parts[0]

        let fields = parts[levelIndex + 1].components(separatedBy: "#")
        guard fields.count >= 8,
              let cols = Int(fields[3]),
              let rows = Int(fields[4]),
              let frameCount = Int(fields[2]),
              cols > 0, cols <= Self.maxGridDimension,
              rows > 0, rows <= Self.maxGridDimension,
              frameCount > 0, frameCount <= Self.maxFrameCount
        else {
            return nil
        }
        let name = fields[6]
        let sigh = fields[7]

        let perSheet = cols * rows
        let sheetCount = min(
            Int((Double(frameCount) / Double(perSheet)).rounded(.up)),
            maxSheets
        )
        guard sheetCount > 0 else { return nil }

        var urls: [URL] = []
        for sheet in 0 ..< sheetCount {
            let resolved = base
                .replacingOccurrences(of: "$L", with: String(levelIndex))
                .replacingOccurrences(of: "$N", with: name)
                .appending("&sigh=\(sigh)")
                .replacingOccurrences(of: "$M", with: String(sheet))
            // The spec comes from the WebView; only fetch it natively when it
            // resolves to an https YouTube image host, so a hostile/mutated
            // spec can't point native requests at private/non-YouTube hosts.
            if let url = URL(string: resolved), Self.isAllowedStoryboardURL(url) {
                urls.append(url)
            }
        }
        guard !urls.isEmpty else { return nil }

        self.sheetURLs = urls
        self.cols = cols
        self.rows = rows
        self.frameCount = frameCount
        self.intervalMilliseconds = max(Int(fields[5]) ?? 0, 0)
    }

    /// The level whose frames suit a hover preview: the smallest one at least 160 px
    /// wide (sharp but light to fetch), else the largest available. `nil` when the
    /// spec has no levels.
    static func previewLevel(in spec: String) -> Int? {
        let widths = spec.components(separatedBy: "|").dropFirst().map {
            Int($0.components(separatedBy: "#").first ?? "") ?? 0
        }
        guard !widths.isEmpty else { return nil }
        if let level = widths.firstIndex(where: { $0 >= 160 }) {
            return level
        }
        return widths.indices.max { widths[$0] < widths[$1] }
    }

    /// Index of the frame to show for a position in the video.
    func frameIndex(atFraction fraction: Double, duration: TimeInterval) -> Int {
        guard self.frameCount > 0, fraction.isFinite else { return 0 }
        let clamped = min(max(fraction, 0), 1)
        let raw: Double = if self.intervalMilliseconds > 0, duration > 0 {
            clamped * duration * 1000 / Double(self.intervalMilliseconds)
        } else {
            clamped * Double(self.frameCount)
        }
        return min(max(Int(raw.rounded(.down)), 0), self.frameCount - 1)
    }

    /// Which sheet (index into `sheetURLs`) holds `frame`.
    func sheetIndex(ofFrame frame: Int) -> Int? {
        let perSheet = self.cols * self.rows
        guard frame >= 0, frame < self.frameCount, perSheet > 0 else { return nil }
        let sheet = frame / perSheet
        return sheet < self.sheetURLs.count ? sheet : nil
    }

    /// The sheet (index into `sheetURLs`) and crop rect holding `frame`, from the
    /// fetched sheet's real pixel size. `nil` when the sheet isn't one we track.
    func location(ofFrame frame: Int, pixelWidth width: Int, height: Int) -> (sheet: Int, rect: CGRect)? {
        let perSheet = self.cols * self.rows
        guard frame >= 0, frame < self.frameCount, perSheet > 0 else { return nil }
        let sheet = frame / perSheet
        guard sheet < self.sheetURLs.count else { return nil }
        let cell = frame % perSheet
        let cellWidth = width / self.cols
        let cellHeight = height / self.rows
        guard cellWidth > 0, cellHeight > 0 else { return nil }
        let rect = CGRect(
            x: (cell % self.cols) * cellWidth,
            y: (cell / self.cols) * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
        return (sheet, rect)
    }

    /// Row-major crop rects (top-left origin, matching `CGImage.cropping`) for
    /// the real frames on the sheet at `sheetIndex`, derived from the actual
    /// fetched sheet pixel dimensions so we don't trust the spec's nominal cell
    /// size. The last sheet is capped to the remaining frames so padding cells
    /// (when `frameCount` isn't an exact multiple of the grid) aren't sampled —
    /// otherwise the tail color would stick across the padded cells.
    func cellRects(forSheetAt sheetIndex: Int, pixelWidth width: Int, height: Int) -> [CGRect] {
        let cellW = width / self.cols
        let cellH = height / self.rows
        guard cellW > 0, cellH > 0 else { return [] }
        let perSheet = self.cols * self.rows
        let remaining = self.frameCount - sheetIndex * perSheet
        guard remaining > 0 else { return [] }
        let cellsOnThisSheet = min(perSheet, remaining)
        var rects: [CGRect] = []
        for cell in 0 ..< cellsOnThisSheet {
            let row = cell / self.cols
            let col = cell % self.cols
            rects.append(CGRect(
                x: col * cellW,
                y: row * cellH,
                width: cellW,
                height: cellH
            ))
        }
        return rects
    }

    /// Whether a resolved storyboard URL is safe to fetch natively: `https`
    /// scheme on a YouTube image host. Guards the WebView→native trust boundary.
    private static func isAllowedStoryboardURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased()
        else {
            return false
        }
        return host == "ytimg.com" || host.hasSuffix(".ytimg.com")
    }
}
