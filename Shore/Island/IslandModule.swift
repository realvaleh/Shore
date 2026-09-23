import AppKit
import SwiftUI

@MainActor
final class IslandModule {
    private let session: IslandSession
    private let settings: ShoreSettings
    private let panel: OverlayPanel
    private let surface: IslandSurfaceView
    private let host: IslandHost
    private var monitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private var collapseWork: DispatchWorkItem?

    init(nowPlaying: NowPlayingStore, chips: LiveChipStore, settings: ShoreSettings, shelf: FileShelfStore) {
        let session = IslandSession()
        self.session = session
        self.settings = settings

        let screen = ScreenGeometry.primary
        // Assign notch geometry without calling instance methods during init (Swift 6).
        session.hugsNotch = ScreenGeometry.hugsNotch(on: screen)
        let notch = ScreenGeometry.notchSize(on: screen) ?? .zero
        session.notchWidth = notch.width
        session.notchHeight = notch.height

        let sessionRef = session
        host = IslandHost(
            rootView: IslandRootView(
                session: session,
                nowPlaying: nowPlaying,
                chips: chips,
                shelf: shelf,
                settings: settings,
                onToggle: { sessionRef.pin() },
                onCollapse: { sessionRef.collapseExplicitly() }
            )
        )
        host.sizingOptions = []
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = NSColor.clear.cgColor
        host.view.autoresizingMask = [.width, .height]

        let size = IslandPlacement.panelSize(on: screen)
        surface = IslandSurfaceView(frame: NSRect(origin: .zero, size: size))
        surface.wantsLayer = true
        surface.layer?.backgroundColor = NSColor.clear.cgColor
        surface.addSubview(host.view)
        host.view.frame = surface.bounds

        panel = OverlayPanel(size: size, interactive: true)
        panel.contentView = surface
        panel.setFrame(IslandPlacement.panelFrame(on: screen), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            panel.animator().alphaValue = 1
        }

        surface.registerForDraggedTypes([.fileURL])
        surface.chromeRectInView = { [weak self] in
            guard let self else { return .zero }
            return IslandPlacement.chromeRect(in: self.surface.bounds, size: self.currentChromeSize())
        }
        surface.chromeContains = { [weak self] point in
            guard let self else { return false }
            let size = self.currentChromeSize()
            let chrome = IslandPlacement.chromeRect(in: self.surface.bounds, size: size)
            let shape = IslandBlendShape.island(
                hugsNotch: self.session.hugsNotch,
                notchWidth: self.session.notchWidth,
                notchHeight: self.session.notchHeight,
                pinned: self.session.isPinned,
                hovering: self.session.isHovering
            )
            return shape.contains(viewPoint: point, chromeRect: chrome)
        }
        surface.onPointerChange = { [weak self] in
            self?.considerMouse(NSEvent.mouseLocation)
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Self.deliver { self?.relayoutPanel() }
        }

        installPointerMonitors()
        considerMouse(NSEvent.mouseLocation)
    }

    func invalidate() {
        collapseWork?.cancel()
        collapseWork = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let panel = self?.panel else { return }
                panel.orderOut(nil)
                panel.close()
            }
        }
    }

    private func installPointerMonitors() {
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseUp, .rightMouseUp
        ]
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Self.deliver { self?.considerMouse(NSEvent.mouseLocation) }
            return event
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Self.deliver { self?.considerMouse(NSEvent.mouseLocation) }
        }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        let localClick = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            Self.deliver { self?.unpinIfOutside() }
            return event
        }
        let globalClick = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            Self.deliver { self?.unpinIfOutside() }
        }
        if let local { monitors.append(local) }
        if let global { monitors.append(global) }
        if let localClick { monitors.append(localClick) }
        if let globalClick { monitors.append(globalClick) }
    }

    private func considerMouse(_ point: CGPoint) {
        let screen = ScreenGeometry.primary
        applyScreen(screen)
        let size = currentChromeSize()
        var zone = IslandPlacement.hoverZone(
            chromeSize: size,
            hovering: session.isHovering,
            pinned: session.isPinned,
            on: screen
        )
        let draggingFiles = settings.fileShelfEnabled && Self.dragPasteboardHasFiles()
        if draggingFiles {
            zone = zone.insetBy(dx: -72, dy: -72)
        }
        let inside = zone.contains(point)
        if session.acceptingFiles != (draggingFiles && inside) {
            session.acceptingFiles = draggingFiles && inside
        }
        if inside {
            if session.hoverSuspended, !draggingFiles {
                return
            }
            setHovering(true)
        } else {
            session.hoverSuspended = false
            setHovering(false)
        }
    }

    private func setHovering(_ on: Bool) {
        if on {
            collapseWork?.cancel()
            collapseWork = nil
            if !session.isHovering {
                shoreAnimate { session.isHovering = true }
            }
            return
        }
        guard session.isHovering else { return }
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.session.isHovering else { return }
            shoreAnimate { self.session.isHovering = false }
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07, execute: work)
    }

    private func unpinIfOutside() {
        guard session.isPinned else { return }
        let size = currentChromeSize()
        let chrome = IslandPlacement.hoverZone(
            chromeSize: size,
            hovering: true,
            pinned: true,
            on: ScreenGeometry.primary
        )
        if !chrome.contains(NSEvent.mouseLocation) {
            session.hoverSuspended = false
            shoreAnimate {
                session.isPinned = false
                session.isHovering = false
            }
        }
    }

    private func relayoutPanel() {
        let screen = ScreenGeometry.primary
        applyScreen(screen)
        let frame = IslandPlacement.panelFrame(on: screen)
        panel.setFrame(frame, display: true)
        surface.setFrameSize(frame.size)
        host.view.setFrameSize(frame.size)
        considerMouse(NSEvent.mouseLocation)
    }

    private func applyScreen(_ screen: NSScreen) {
        session.hugsNotch = ScreenGeometry.hugsNotch(on: screen)
        let notch = ScreenGeometry.notchSize(on: screen) ?? .zero
        session.notchWidth = notch.width
        session.notchHeight = notch.height
    }

    private func currentChromeSize() -> CGSize {
        IslandPlacement.chromeSize(
            hovering: session.isHovering,
            pinned: session.isPinned,
            hugsNotch: session.hugsNotch,
            notch: CGSize(width: session.notchWidth, height: session.notchHeight),
            shelfVisible: settings.fileShelfEnabled && (session.isHovering || session.isPinned)
        )
    }

    private static func dragPasteboardHasFiles() -> Bool {
        let pasteboard = NSPasteboard(name: .drag)
        return pasteboard.availableType(from: [.fileURL]) != nil
    }

    /// Pointer monitors are added on the main thread; hop only when Swift 6 isolation requires it.
    nonisolated private static func deliver(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            DispatchQueue.main.async { work() }
        }
    }
}
