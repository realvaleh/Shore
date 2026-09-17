import AppKit

/// Borderless floating panel used by both Island (interactive) and Tide Line (click-through).
@MainActor
final class OverlayPanel: NSPanel {
    init(size: NSSize, interactive: Bool) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        /// System utility animation made the island feel a beat late; we spring in SwiftUI.
        animationBehavior = .none
        ignoresMouseEvents = !interactive
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
    }

    override var canBecomeKey: Bool { !ignoresMouseEvents }
    override var canBecomeMain: Bool { false }
}

/// Hosts Island SwiftUI and hit-tests only the chrome so transparent panel wings stay click-through.
@MainActor
final class IslandSurfaceView: NSView {
    var chromeRectInView: () -> NSRect = { .zero }
    var onPointerChange: () -> Void = {}

    override var isFlipped: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let chrome = chromeRectInView()
        guard chrome.contains(point) else { return nil }
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeAlways,
            .inVisibleRect,
            .enabledDuringMouseDrag
        ]
        addTrackingArea(NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerChange()
    }

    override func mouseExited(with event: NSEvent) {
        onPointerChange()
    }

    override func mouseMoved(with event: NSEvent) {
        onPointerChange()
    }

    override func mouseDragged(with event: NSEvent) {
        onPointerChange()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
