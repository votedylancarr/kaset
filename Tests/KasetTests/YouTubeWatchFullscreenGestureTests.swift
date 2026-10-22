import Testing
@testable import Kaset

@Suite("YouTube double-click fullscreen", .tags(.service))
@MainActor
struct YouTubeWatchFullscreenGestureTests {
    @Test("Double-clicking the video asks Kaset to toggle its own fullscreen")
    func doubleClickRoutesToNativeFullscreen() {
        let script = YouTubeWatchWebView.observerScript

        #expect(script.contains("addEventListener('dblclick'"))
        #expect(script.contains("type: 'TOGGLE_FULLSCREEN'"))
        // The page must not also fullscreen itself, and the message must carry the document
        // generation so stale pages are rejected like every other bridge message.
        #expect(script.contains("event.preventDefault()"))
        #expect(script.contains("event.stopImmediatePropagation()"))
        #expect(script.contains("""
        type: 'TOGGLE_FULLSCREEN',
                        documentGeneration: window.__kasetDocumentGeneration
        """))
    }

    @Test("The page's own fullscreen is only guarded on controls, not the video")
    func controlsKeepTheirOwnDoubleClick() {
        let script = YouTubeWatchWebView.observerScript

        #expect(script.contains(".ytp-chrome-bottom"))
        #expect(script.contains("closest('#movie_player')"))
    }
}
