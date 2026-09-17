import AppKit
import SwiftUI

/// Borderless floating panel used by both Island (interactive) and Dock Cove (chrome-only hit testing).
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

/// SwiftUI host that does not inherit the camera-housing safe-area (that inset is the gap).
@MainActor
final class IslandHost: NSHostingController<IslandRootView> {
    override func viewDidLoad() {
        super.viewDidLoad()
        flushSafeArea()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        flushSafeArea()
    }

    private func flushSafeArea() {
        view.additionalSafeAreaInsets = NSEdgeInsets()
        sizingOptions = []
        if #available(macOS 14.0, *) {
            (view as? NSHostingView<IslandRootView>)?.safeAreaRegions = []
        }
    }
}

/// Hosts Island SwiftUI and hit-tests only the chrome so transparent panel wings stay click-through.
@MainActor
final class IslandSurfaceView: NSView {
    var chromeRectInView: () -> NSRect = { .zero }
    var chromeContains: ((NSPoint) -> Bool)?
    var onPointerChange: () -> Void = {}

    override var isFlipped: Bool { false }

    /// Hosting views otherwise inherit the camera-housing inset and float the chrome below it.
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hits: Bool
        if let chromeContains {
            hits = chromeContains(point)
        } else {
            hits = chromeRectInView().contains(point)
        }
        guard hits else { return nil }
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
