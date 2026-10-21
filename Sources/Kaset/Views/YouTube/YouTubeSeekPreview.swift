import AppKit
import Observation
import SwiftUI

// MARK: - YouTubeSeekPreviewModel

/// Supplies the thumbnail shown above the seek bar while hovering or scrubbing.
///
/// Frames come from YouTube's storyboard sprite sheets (plain JPEGs, not DRM
/// protected). A sheet is fetched the first time a frame on it is needed, then the
/// frame is cropped out; sheets and cropped frames are cached for the video.
@MainActor
@Observable
final class YouTubeSeekPreviewModel {
    /// The frame for the latest requested position, or `nil` before the first loads.
    private(set) var image: NSImage?

    private var sheet: StoryboardSheet?
    private var specKey: String?
    private var sheetImages: [Int: CGImage] = [:]
    private var loadingSheets: Set<Int> = []
    private var frameCache: [Int: NSImage] = [:]
    private var requestedFrame: Int?

    /// Whether this video has storyboards to preview from.
    var isAvailable: Bool {
        self.sheet != nil
    }

    /// Points the model at a video's storyboard spec; a different spec resets it.
    func configure(spec: String?) {
        guard spec != self.specKey else { return }
        self.specKey = spec
        self.sheetImages = [:]
        self.loadingSheets = []
        self.frameCache = [:]
        self.requestedFrame = nil
        self.image = nil
        guard let spec, let level = StoryboardSheet.previewLevel(in: spec) else {
            self.sheet = nil
            return
        }
        self.sheet = StoryboardSheet(spec: spec, level: level, maxSheets: 60)
    }

    /// Requests the frame for `fraction` of the video. Until a sheet arrives the
    /// previous frame stays up, so the preview doesn't flicker while scrubbing.
    func show(fraction: Double, duration: TimeInterval) {
        guard let sheet else { return }
        let frame = sheet.frameIndex(atFraction: fraction, duration: duration)
        self.requestedFrame = frame
        if let cached = self.frameCache[frame] {
            self.image = cached
            return
        }
        if let needed = sheet.sheetIndex(ofFrame: frame), self.sheetImages[needed] == nil {
            self.loadSheet(needed, of: sheet)
        }
        self.cropIfPossible(frame: frame, sheet: sheet)
    }

    func hide() {
        self.requestedFrame = nil
    }

    // MARK: - Loading

    private func loadSheet(_ index: Int, of sheet: StoryboardSheet) {
        guard !self.loadingSheets.contains(index), sheet.sheetURLs.indices.contains(index) else { return }
        self.loadingSheets.insert(index)
        let url = sheet.sheetURLs[index]
        let key = self.specKey
        Task { [weak self] in
            let loaded = await ImageCache.shared.image(for: url)
            guard let self, self.specKey == key else { return }
            self.loadingSheets.remove(index)
            guard let cgImage = loaded?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            self.sheetImages[index] = cgImage
            if let sheet = self.sheet, let requested = self.requestedFrame {
                self.cropIfPossible(frame: requested, sheet: sheet)
            }
        }
    }

    private func cropIfPossible(frame: Int, sheet: StoryboardSheet) {
        guard let sheetIndex = sheet.sheetIndex(ofFrame: frame),
              let cgImage = self.sheetImages[sheetIndex],
              let located = sheet.location(ofFrame: frame, pixelWidth: cgImage.width, height: cgImage.height),
              let cropped = cgImage.cropping(to: located.rect)
        else { return }
        let image = NSImage(cgImage: cropped, size: NSSize(width: located.rect.width, height: located.rect.height))
        if self.frameCache.count > 400 {
            self.frameCache.removeAll()
        }
        self.frameCache[frame] = image
        if self.requestedFrame == frame {
            self.image = image
        }
    }
}

// MARK: - YouTubeSeekPreviewCard

/// The floating preview: a video frame, the time under the pointer and, when the
/// video has chapters, the chapter title.
struct YouTubeSeekPreviewCard: View {
    static let imageSize = CGSize(width: 176, height: 99)

    let image: NSImage?
    let timeText: String
    let chapterTitle: String?

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(.black)
                }
            }
            .frame(width: Self.imageSize.width, height: Self.imageSize.height)
            .clipShape(.rect(cornerRadius: 8, style: .continuous))

            VStack(spacing: 1) {
                if let chapterTitle {
                    Text(chapterTitle)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
                Text(self.timeText)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(chapterTitle == nil ? .primary : .secondary)
            }
            .frame(maxWidth: Self.imageSize.width)
        }
        .padding(6)
        .compatGlass(in: .rect(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .accessibilityHidden(true)
    }
}
