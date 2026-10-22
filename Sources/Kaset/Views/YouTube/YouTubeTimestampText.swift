import SwiftUI

// MARK: - YouTubeTimestampLinker

/// Finds timestamps like `1:23` or `1:02:45` in text and turns them into links that
/// seek the video. The links use a private scheme that the watch page intercepts.
enum YouTubeTimestampLinker {
    /// URL scheme for a seek link; the host is the target in whole seconds.
    static let scheme = "kaset-seek"

    /// `m:ss` or `h:mm:ss`, not glued to other digits or separators, and not a clock time
    /// ("10:30pm") or part of a decimal.
    private static let pattern = try? NSRegularExpression(
        pattern: #"(?<![\d:.,/])(?:(\d{1,2}):)?([0-5]?\d):([0-5]\d)(?![\d:])(?!\.\d)(?!\s?[AaPp]\.?[Mm]\b)"#
    )

    struct Match: Equatable {
        let range: Range<String.Index>
        let seconds: Int
    }

    static func matches(in text: String) -> [Match] {
        guard let pattern else { return [] }
        let whole = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: whole).compactMap { match in
            guard let range = Range(match.range, in: text),
                  let minutes = Self.value(of: match.range(at: 2), in: text),
                  let seconds = Self.value(of: match.range(at: 3), in: text)
            else { return nil }
            let hours = Self.value(of: match.range(at: 1), in: text) ?? 0
            return Match(range: range, seconds: hours * 3600 + minutes * 60 + seconds)
        }
    }

    /// The text with every timestamp made a tappable seek link.
    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString()
        var cursor = text.startIndex
        for match in self.matches(in: text) {
            result += AttributedString(String(text[cursor ..< match.range.lowerBound]))
            var link = AttributedString(String(text[match.range]))
            link.link = self.url(forSeconds: match.seconds)
            result += link
            cursor = match.range.upperBound
        }
        result += AttributedString(String(text[cursor...]))
        return result
    }

    static func url(forSeconds seconds: Int) -> URL? {
        URL(string: "\(self.scheme)://\(seconds)")
    }

    /// The target of a seek link, or `nil` for any other URL.
    static func seconds(from url: URL) -> TimeInterval? {
        guard url.scheme == self.scheme, let host = url.host, let seconds = Int(host) else { return nil }
        return TimeInterval(seconds)
    }

    private static func value(of range: NSRange, in text: String) -> Int? {
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return Int(text[swiftRange])
    }
}

// MARK: - YouTubeLinkedText

/// Text whose timestamps are clickable. A click is handled by the nearest
/// `openURL` action (the watch page seeks the video).
struct YouTubeLinkedText: View {
    let text: String
    var font: Font = .system(size: 12)

    var body: some View {
        Text(YouTubeTimestampLinker.attributed(self.text))
            .font(self.font)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
    }
}

// MARK: - YouTubeDescriptionSection

/// The video's description in a card: three lines with Show more, and clickable
/// timestamps.
struct YouTubeDescriptionSection: View {
    let text: String

    @State private var isExpanded = false

    /// Short descriptions have nothing to expand.
    private var canExpand: Bool {
        self.text.count > 180 || self.text.split(separator: "\n", omittingEmptySubsequences: false).count > 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            YouTubeLinkedText(text: self.text, font: .callout)
                .lineLimit(self.isExpanded ? nil : 3)
                .frame(maxWidth: .infinity, alignment: .leading)

            if self.canExpand {
                Button {
                    withAnimation(.smooth(duration: 0.25)) { self.isExpanded.toggle() }
                } label: {
                    Text(self.isExpanded ? String(localized: "Show less") : String(localized: "Show more"))
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(AccessibilityID.YouTubeContent.descriptionToggle)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10, style: .continuous))
        .accessibilityIdentifier(AccessibilityID.YouTubeContent.descriptionSection)
    }
}

// MARK: - AccessibilityID Additions

extension AccessibilityID.YouTubeContent {
    static let descriptionSection = "youtubeContent.descriptionSection"
    static let descriptionToggle = "youtubeContent.descriptionToggle"
}
