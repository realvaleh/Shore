import AppKit
import Combine
import SwiftUI

@MainActor
final class IslandModule {
    private let session: IslandSession
    private let nowPlaying: NowPlayingStore
    private let chips: LiveChipStore
    private let panel: OverlayPanel
    private let host: NSHostingController<IslandRootView>
    private var expandCancellable: AnyCancellable?
    private var monitors: [Any] = []
    private var screenObserver: NSObjectProtocol?

    init(nowPlaying: NowPlayingStore, chips: LiveChipStore) {
        let session = IslandSession()
        self.session = session
        self.nowPlaying = nowPlaying
        self.chips = chips

        let screen = ScreenGeometry.primary
        session.hugsNotch = ScreenGeometry.hugsNotch(on: screen)
        let size = Self.size(expanded: false, on: screen)

        let sessionRef = session
        host = NSHostingController(
            rootView: IslandRootView(
                session: session,
                nowPlaying: nowPlaying,
                chips: chips,
                onToggle: { sessionRef.isExpanded.toggle() },
                onCollapse: { sessionRef.isExpanded = false }
            )
        )
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = NSColor.clear.cgColor
        host.view.autoresizingMask = [.width, .height]

        panel = OverlayPanel(size: size, interactive: true)
        panel.contentView = host.view
        panel.setFrame(IslandPlacement.frame(size: size, on: screen), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            panel.animator().alphaValue = 1
        }

        expandCancellable = session.$isExpanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                Task { @MainActor in
                    self?.layout(expanded: expanded, animated: true)
                }
            }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.layout(expanded: self?.session.isExpanded ?? false, animated: false)
            }
        }

        let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.collapseIfOutside()
            }
            return event
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.collapseIfOutside()
            }
        }
        if let local { monitors.append(local) }
        if let global { monitors.append(global) }
    }

    func invalidate() {
        expandCancellable = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let panel = self?.panel else { return }
                panel.orderOut(nil)
                panel.close()
            }
        }
    }

    private func collapseIfOutside() {
        guard session.isExpanded else { return }
        if !panel.frame.contains(NSEvent.mouseLocation) {
            session.isExpanded = false
        }
    }

    private func layout(expanded: Bool, animated: Bool) {
        let screen = ScreenGeometry.primary
        session.hugsNotch = ScreenGeometry.hugsNotch(on: screen)
        let size = Self.size(expanded: expanded, on: screen)
        let frame = IslandPlacement.frame(size: size, on: screen)
        host.view.setFrameSize(size)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.42
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private static func size(expanded: Bool, on screen: NSScreen) -> CGSize {
        let collapsedWidth = IslandPlacement.collapsedWidth(on: screen)
        let extraTop: CGFloat = ScreenGeometry.hugsNotch(on: screen) ? 10 : 0
        if expanded {
            return CGSize(
                width: max(IslandMetrics.expandedSize.width, collapsedWidth),
                height: IslandMetrics.expandedSize.height + extraTop
            )
        }
        return CGSize(width: collapsedWidth, height: IslandMetrics.collapsedHeight + extraTop)
    }
}
