import AppKit

@MainActor
enum ScreenGeometry {
    static var primary: NSScreen {
        NSScreen.main ?? NSScreen.screens[0]
    }

    static func menuBarHeight(on screen: NSScreen) -> CGFloat {
        max(0, screen.frame.maxY - screen.visibleFrame.maxY)
    }

    /// Bottom Dock only. Side Dock returns 0 — Tide Line hides in that case.
    static func bottomDockHeight(on screen: NSScreen) -> CGFloat {
        max(0, screen.visibleFrame.minY - screen.frame.minY)
    }

    /// Hardware camera housing width, if this display has one.
    static func notchWidth(on screen: NSScreen) -> CGFloat? {
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else { return nil }
        let width = screen.frame.width - left.width - right.width
        guard width > 48, left.width > 0, right.width > 0 else { return nil }
        return width
    }

    static func hugsNotch(on screen: NSScreen) -> Bool {
        notchWidth(on: screen) != nil
    }
}

@MainActor
enum IslandPlacement {
    static func collapsedWidth(on screen: NSScreen) -> CGFloat {
        if let notch = ScreenGeometry.notchWidth(on: screen) {
            return max(IslandMetrics.collapsedMinWidth, notch + IslandMetrics.notchSideLip * 2)
        }
        return IslandMetrics.collapsedMinWidth
    }

    static func origin(size: CGSize, on screen: NSScreen) -> CGPoint {
        let frame = screen.frame
        let x = frame.midX - size.width / 2
        if ScreenGeometry.hugsNotch(on: screen) {
            return CGPoint(x: x, y: frame.maxY - size.height)
        }
        let y = frame.maxY
            - ScreenGeometry.menuBarHeight(on: screen)
            - IslandMetrics.floatingGap
            - size.height
        return CGPoint(x: x, y: y)
    }

    static func frame(size: CGSize, on screen: NSScreen) -> NSRect {
        NSRect(origin: origin(size: size, on: screen), size: size)
    }
}
