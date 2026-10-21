import SwiftUI

// MARK: - Queue context menu

extension View {
    /// Right-click menu to queue a video: Play Next, and Add to / Remove from Queue.
    func youtubeQueueContextMenu(_ video: YouTubeVideo) -> some View {
        self.modifier(YouTubeQueueContextMenuModifier(video: video))
    }
}

// MARK: - YouTubeQueueContextMenuModifier

private struct YouTubeQueueContextMenuModifier: ViewModifier {
    @Environment(YouTubePlayerService.self) private var youtubePlayer

    let video: YouTubeVideo

    func body(content: Content) -> some View {
        content.contextMenu {
            if self.youtubePlayer.canQueue(self.video) {
                Button {
                    self.youtubePlayer.playNext(self.video)
                    HapticService.toggle()
                } label: {
                    Label(String(localized: "Play Next"), systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                .disabled(self.video.videoId == self.youtubePlayer.currentVideo?.videoId)

                if self.youtubePlayer.isQueued(self.video) {
                    Button {
                        self.youtubePlayer.removeFromQueue(self.video)
                    } label: {
                        Label(String(localized: "Remove from Queue"), systemImage: "text.badge.minus")
                    }
                } else {
                    Button {
                        self.youtubePlayer.addToQueue(self.video)
                        HapticService.toggle()
                    } label: {
                        Label(String(localized: "Add to Queue"), systemImage: "text.badge.plus")
                    }
                    .disabled(self.video.videoId == self.youtubePlayer.currentVideo?.videoId)
                }
            }
        }
    }
}

// MARK: - YouTubeQueuePanel

/// The user's queue above the related list: reorder by dragging, click to play now,
/// remove one, or clear all. Hidden while the queue is empty.
struct YouTubeQueuePanel: View {
    @Environment(YouTubePlayerService.self) private var youtubePlayer

    private static let rowHeight: CGFloat = 60
    private static let maxVisibleRows = 5

    var body: some View {
        let queue = self.youtubePlayer.userQueue
        if !queue.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Queue", comment: "Queued videos section header")
                        .font(.title3.bold())
                    Text("\(queue.count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button {
                        withAnimation(.smooth(duration: 0.25)) { self.youtubePlayer.clearQueue() }
                    } label: {
                        Text("Clear Queue", comment: "Remove every queued video")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AccessibilityID.YouTubeContent.queueClearButton)
                }

                List {
                    ForEach(queue) { video in
                        QueueRow(video: video)
                            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onMove { source, destination in
                        self.youtubePlayer.moveInQueue(fromOffsets: source, toOffset: destination)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(height: CGFloat(min(queue.count, Self.maxVisibleRows)) * Self.rowHeight)
                .accessibilityIdentifier(AccessibilityID.YouTubeContent.queueList)

                Divider()
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: - QueueRow

private struct QueueRow: View {
    @Environment(YouTubePlayerService.self) private var youtubePlayer
    @State private var isHovering = false

    let video: YouTubeVideo

    var body: some View {
        HStack(spacing: 10) {
            VideoThumbnailView(video: self.video, targetSize: CGSize(width: 160, height: 90))
                .frame(width: 88)

            VStack(alignment: .leading, spacing: 2) {
                Text(self.video.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                if let channel = self.video.channelName {
                    Text(channel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(.smooth(duration: 0.25)) { self.youtubePlayer.removeFromQueue(self.video) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(self.isHovering ? 1 : 0)
            .help(String(localized: "Remove from Queue"))
        }
        .contentShape(Rectangle())
        .onHover { self.isHovering = $0 }
        .onTapGesture {
            self.youtubePlayer.playQueuedVideo(self.video)
        }
        .contextMenu {
            Button {
                self.youtubePlayer.playQueuedVideo(self.video)
            } label: {
                Label(String(localized: "Play Now"), systemImage: "play.fill")
            }
            Button {
                self.youtubePlayer.playNext(self.video)
            } label: {
                Label(String(localized: "Move to Top"), systemImage: "arrow.up.to.line")
            }
            Button(role: .destructive) {
                self.youtubePlayer.removeFromQueue(self.video)
            } label: {
                Label(String(localized: "Remove from Queue"), systemImage: "text.badge.minus")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - AccessibilityID Additions

extension AccessibilityID.YouTubeContent {
    static let queueList = "youtubeContent.queueList"
    static let queueClearButton = "youtubeContent.queueClearButton"
}

// MARK: - RelatedVideoRow

/// Compact related-rail row sized for the right column.
struct RelatedVideoRow: View {
    let video: YouTubeVideo

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VideoThumbnailView(video: self.video)
                .frame(width: 140)

            VStack(alignment: .leading, spacing: 3) {
                Text(self.video.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let channelName = self.video.channelName {
                    Text(channelName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let viewCountText = self.video.viewCountText {
                    Text(viewCountText)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .youtubeQueueContextMenu(self.video)
    }
}
