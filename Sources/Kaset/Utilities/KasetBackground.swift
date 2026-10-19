import AppKit
import SwiftUI

// MARK: - Kaset app background

extension NSColor {
    /// The app's base background: true black in dark mode, the standard window
    /// background in light mode. Dynamic, so it follows appearance changes.
    static let kasetBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.black
            : NSColor.windowBackgroundColor
    }
}

extension NSColor {
    /// A mostly-black wash for the sidebar's glass in dark mode, so the sidebar
    /// matches the black app background while still letting a little of the
    /// ambient glow through. Clear in light mode.
    static let kasetSidebarTint = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.black.withAlphaComponent(0.7)
            : NSColor.clear
    }
}

extension Color {
    /// SwiftUI form of `NSColor.kasetBackground`.
    static var kasetBackground: Color {
        Color(nsColor: .kasetBackground)
    }
}
