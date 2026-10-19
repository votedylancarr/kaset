import AppKit

// MARK: - MainWindowCoverageMonitor

/// Reports when the main window becomes fully covered or visible again, using
/// `NSWindow.occlusionState`. A window that is only partly covered still counts as
/// visible. Changes are debounced so Mission Control or Space swipes don't make the
/// video bounce between the window and the floating player.
@MainActor
final class MainWindowCoverageMonitor {
    /// Delay before treating a state change as real.
    nonisolated static let coveredDelay: Duration = .milliseconds(600)
    nonisolated static let visibleDelay: Duration = .milliseconds(200)

    private var observer: NSObjectProtocol?
    private var pending: Task<Void, Never>?
    private weak var window: NSWindow?
    private var onChange: (@MainActor (Bool) -> Void)?
    private var lastReportedCovered = false

    func observe(_ window: NSWindow, onChange: @escaping @MainActor (Bool) -> Void) {
        self.stop()
        self.window = window
        self.onChange = onChange
        // Windows register before they are shown; treat that as visible.
        self.lastReportedCovered = false
        self.observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.occlusionChanged() }
        }
    }

    func stop() {
        self.pending?.cancel()
        self.pending = nil
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        self.observer = nil
        self.window = nil
        self.onChange = nil
    }

    private func occlusionChanged() {
        guard let window else { return }
        let isCovered = !window.occlusionState.contains(.visible)
        self.pending?.cancel()
        guard isCovered != self.lastReportedCovered else { return }
        self.pending = Task { [weak self] in
            do {
                try await Task.sleep(for: isCovered ? Self.coveredDelay : Self.visibleDelay)
            } catch {
                return
            }
            guard let self, let window = self.window,
                  !window.occlusionState.contains(.visible) == isCovered
            else { return }
            self.lastReportedCovered = isCovered
            self.onChange?(isCovered)
        }
    }
}
