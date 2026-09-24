import AppKit

@MainActor
enum ScreenGeometry {
    static var primary: NSScreen {
        NSScreen.main ?? NSScreen.screens[0]
    }

    static func menuBarHeight(on screen: NSScreen) -> CGFloat {
        max(0, screen.frame.maxY - screen.visibleFrame.maxY)
    }

    /// Bottom Dock only. Side Dock returns 0. Shore does not draw over the system Dock.
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

    /// Hardware camera housing height (safe-area top, else the auxiliary menu-bar band).
    static func notchHeight(on screen: NSScreen) -> CGFloat? {
        guard hugsNotch(on: screen) else { return nil }
        if screen.safeAreaInsets.top > 0 {
            return screen.safeAreaInsets.top
        }
        if let left = screen.auxiliaryTopLeftArea, left.height > 0 {
            return left.height
        }
        let menu = menuBarHeight(on: screen)
        return menu > 0 ? menu : IslandMetrics.notchHeightFallback
    }

    static func notchSize(on screen: NSScreen) -> CGSize? {
        guard let width = notchWidth(on: screen),
              let height = notchHeight(on: screen)
        else { return nil }
        return CGSize(width: width, height: height)
    }

    /// Screen-space rect of the camera housing, flush with the top of the framebuffer.
    static func notchFrame(on screen: NSScreen) -> NSRect? {
        guard let size = notchSize(on: screen) else { return nil }
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    static func hugsNotch(on screen: NSScreen) -> Bool {
        notchWidth(on: screen) != nil
    }
}

@MainActor
enum IslandPlacement {
    static func restSize(hugsNotch: Bool, notch: CGSize) -> CGSize {
        if hugsNotch, notch.width > 0, notch.height > 0 {
            // Extra height matches the upward bezel nudge so the chin still meets the housing.
            return CGSize(
                width: notch.width,
                height: notch.height + IslandMetrics.bezelFlushNudge
            )
        }
        return CGSize(width: IslandMetrics.collapsedMinWidth, height: IslandMetrics.collapsedHeight)
    }

    /// Notched open states grow a fixed amount past the housing. Floating states use `minimum`.
    static func openWidth(hugsNotch: Bool, notch: CGSize, growth: CGFloat, minimum: CGFloat) -> CGFloat {
        guard hugsNotch, notch.width > 1 else { return minimum }
        return max(minimum, notch.width + growth)
    }

    static func chromeSize(
        hovering: Bool,
        pinned: Bool,
        hugsNotch: Bool,
        notch: CGSize,
        shelfVisible: Bool
    ) -> CGSize {
        let rest = restSize(hugsNotch: hugsNotch, notch: notch)
        let shelf = shelfVisible ? IslandMetrics.shelfHeight : 0

        if pinned {
            let width = openWidth(
                hugsNotch: hugsNotch,
                notch: notch,
                growth: 160,
                minimum: IslandMetrics.expandedSize.width
            )
            let height = hugsNotch
                ? rest.height + IslandMetrics.expandedLip + shelf
                : IslandMetrics.expandedSize.height + shelf
            return CGSize(width: width, height: height)
        }

        if hovering {
            let width = openWidth(
                hugsNotch: hugsNotch,
                notch: notch,
                growth: IslandMetrics.compactGrowth,
                minimum: IslandMetrics.compactWidth
            )
            let height = hugsNotch
                ? rest.height + IslandMetrics.compactLip + shelf
                : 60 + shelf
            return CGSize(width: width, height: height)
        }

        return rest
    }

    /// Always large enough for the pinned + shelf chrome so the window does not resize on hover.
    static func panelSize(on screen: NSScreen) -> CGSize {
        let notch = ScreenGeometry.notchSize(on: screen) ?? .zero
        return chromeSize(
            hovering: true,
            pinned: true,
            hugsNotch: ScreenGeometry.hugsNotch(on: screen),
            notch: notch,
            shelfVisible: true
        )
    }

    static func panelFrame(on screen: NSScreen) -> NSRect {
        let size = panelSize(on: screen)
        let frame = screen.frame
        let x = frame.midX - size.width / 2
        if ScreenGeometry.hugsNotch(on: screen) {
            // 1pt into the bezel hides a backing-store hairline without a visible gap.
            let y = frame.maxY - size.height + IslandMetrics.bezelFlushNudge
            return NSRect(x: x, y: y, width: size.width, height: size.height)
        }
        let y = frame.maxY
            - ScreenGeometry.menuBarHeight(on: screen)
            - IslandMetrics.floatingGap
            - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Screen-space hover probe. Larger than the chrome so the island can wake from the notch;
    /// this zone is monitored via NSEvent and must not be used as a click-stealing hit region.
    static func hoverZone(
        chromeSize: CGSize,
        hovering: Bool,
        pinned: Bool,
        on screen: NSScreen
    ) -> NSRect {
        let panel = panelFrame(on: screen)
        let slop = (hovering || pinned) ? IslandMetrics.hoverSlopStay : IslandMetrics.hoverSlopEnter
        let width = chromeSize.width + (hovering || pinned ? 8 : 4)
        return NSRect(
            x: panel.midX - width / 2,
            y: panel.maxY - chromeSize.height - slop,
            width: width,
            height: chromeSize.height + slop
        )
    }

    /// AppKit view-coordinates (y-up) rect of the chrome, top-centered in the panel.
    static func chromeRect(in bounds: NSRect, size: CGSize) -> NSRect {
        NSRect(
            x: bounds.midX - size.width / 2,
            y: bounds.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
