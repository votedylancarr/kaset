import Foundation

extension YouTubePlayerService {
    /// The user reopened the app window (Dock click). If the floating video's own
    /// page is the one open in the window, dock the video back into it; a video
    /// floating because the user navigated elsewhere keeps floating.
    func dockFloatingVideoOnItsPage() {
        guard self.surfaceLocation == .floating,
              let video = self.currentVideo,
              self.activeInlineVideoId == video.videoId
        else { return }
        self.dockInline()
    }

    /// The main window became fully covered (or visible again). A playing inline
    /// video pops out to the floating window while covered, and docks back when the
    /// window is visible again. Only a pop-out caused by coverage is undone.
    func applyMainWindowCoverage(isCovered: Bool) {
        // Entering or leaving fullscreen switches Spaces, which hides and shows the main
        // window without the user covering anything. Fullscreen is the user's own choice
        // of where the video lives, so coverage never moves it (and docking mid-fullscreen
        // closes the pop-out under its own exit animation).
        if self.isWindowFullscreen {
            self.isPoppedOutForCoverage = false
            return
        }
        if isCovered {
            guard self.shouldPopOutWhenCovered(),
                  self.surfaceLocation == .inline,
                  self.currentVideo != nil,
                  self.isPlaying
            else { return }
            self.popOutToWindow()
            self.isPoppedOutForCoverage = true
        } else {
            guard self.isPoppedOutForCoverage else { return }
            self.isPoppedOutForCoverage = false
            if self.surfaceLocation == .floating {
                self.requestPopIn()
            }
        }
    }
}
