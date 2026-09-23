import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// File basket that appears **only while a file drag is in flight**.
/// Parks drops onto the shared island shelf. Never a second Dock, never a
/// permanent dashed pill above the system Dock.
@MainActor
final class DockModule {
    private let panel: OverlayPanel
    private let surface: BasketSurfaceView
    private let host: NSHostingController<BasketRootView>
    private let model: BasketModel
    private let shelf: FileShelfStore
    private var screenObserver: NSObjectProtocol?
    private var monitors: [Any] = []

    init(shelf: FileShelfStore) {
        let model = BasketModel()
        self.model = model
        self.shelf = shelf
        let screen = ScreenGeometry.primary
        let size = Self.panelSize()

        host = NSHostingController(rootView: BasketRootView(model: model, shelf: shelf))
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = NSColor.clear.cgColor
        host.view.autoresizingMask = [.width, .height]

        surface = BasketSurfaceView(frame: NSRect(origin: .zero, size: size))
        surface.wantsLayer = true
        surface.layer?.backgroundColor = NSColor.clear.cgColor
        surface.addSubview(host.view)
        host.view.frame = surface.bounds
        surface.registerForDraggedTypes([.fileURL])

        panel = OverlayPanel(size: size, interactive: true)
        panel.contentView = surface
        panel.setFrame(Self.panelFrame(on: screen, mouse: NSEvent.mouseLocation), display: true)
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true

        surface.chromeRectInView = { [weak self] in
            guard let self else { return .zero }
            return Self.chromeRect(in: self.surface.bounds)
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Self.deliver { self?.tick() }
        }

        let dragMask: NSEvent.EventTypeMask = [.leftMouseDragged, .rightMouseDragged, .leftMouseUp, .mouseMoved]
        let local = NSEvent.addLocalMonitorForEvents(matching: dragMask) { [weak self] event in
            Self.deliver { self?.tick() }
            return event
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: dragMask) { [weak self] _ in
            Self.deliver { self?.tick() }
        }
        if let local { monitors.append(local) }
        if let global { monitors.append(global) }
        tick()
    }

    func invalidate() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        panel.orderOut(nil)
        panel.close()
    }

    private func tick() {
        let dragging = Self.dragPasteboardHasFiles()
        model.draggingFiles = dragging
        model.pointer = NSEvent.mouseLocation
        applyFrame()
        applyInteractivity()
    }

    private func applyFrame() {
        let screen = ScreenGeometry.primary
        let frame = Self.panelFrame(on: screen, mouse: model.pointer)
        panel.setFrame(frame, display: true)
        surface.setFrameSize(Self.panelSize())
        host.view.setFrameSize(Self.panelSize())
    }

    private func applyInteractivity() {
        let open = model.revealed
        panel.ignoresMouseEvents = !open
        if open {
            panel.orderFrontRegardless()
            if panel.alphaValue < 1 {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    panel.animator().alphaValue = 1
                }
            }
        } else if panel.alphaValue > 0 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    guard let self, !self.model.revealed else { return }
                    self.panel.orderOut(nil)
                }
            }
        }
    }

    private static func dragPasteboardHasFiles() -> Bool {
        let pasteboard = NSPasteboard(name: .drag)
        return pasteboard.availableType(from: [.fileURL]) != nil
    }

    private static func panelSize() -> CGSize {
        CGSize(width: BasketMetrics.width, height: BasketMetrics.height)
    }

    /// Below the pointer so the drag image does not cover the target. If that
    /// would sit on the island, tuck the basket just under the island instead.
    private static func panelFrame(on screen: NSScreen, mouse: CGPoint) -> NSRect {
        let size = panelSize()
        var x = mouse.x - size.width * 0.38
        var y = mouse.y - size.height - 36
        if let notch = ScreenGeometry.notchFrame(on: screen) {
            let band = NSRect(
                x: notch.midX - 210,
                y: notch.minY - IslandMetrics.expandedLip - IslandMetrics.shelfHeight - 8,
                width: 420,
                height: notch.height + IslandMetrics.expandedLip + IslandMetrics.shelfHeight + 16
            )
            let proposed = NSRect(x: x, y: y, width: size.width, height: size.height)
            if proposed.intersects(band), mouse.y >= band.minY - 24 {
                x = min(max(band.minX + 12, mouse.x - size.width * 0.38), band.maxX - size.width - 12)
                y = band.minY - size.height - 8
            }
        }
        let pad: CGFloat = 8
        x = min(max(screen.frame.minX + pad, x), screen.frame.maxX - size.width - pad)
        y = min(max(screen.frame.minY + pad, y), screen.frame.maxY - size.height - pad)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    static func chromeRect(in bounds: NSRect) -> NSRect {
        bounds.insetBy(dx: 4, dy: 4)
    }

    nonisolated private static func deliver(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            DispatchQueue.main.async { work() }
        }
    }
}

enum BasketMetrics {
    static let width: CGFloat = 236
    static let height: CGFloat = 58
}

@MainActor
final class BasketModel: ObservableObject {
    @Published var draggingFiles = false
    @Published var targeted = false
    @Published var pointer: CGPoint = .zero

    var revealed: Bool { draggingFiles || targeted }
}

/// Hit-tests only the basket chrome so the rest of the desktop stays clickable.
@MainActor
final class BasketSurfaceView: NSView {
    var chromeRectInView: () -> NSRect = { .zero }

    override var isFlipped: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let chrome = chromeRectInView().insetBy(dx: -2, dy: -2)
        guard chrome.contains(point) else { return nil }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct BasketRootView: View {
    @ObservedObject var model: BasketModel
    @ObservedObject var shelf: FileShelfStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var morph: Animation { reduceMotion ? .shoreQuiet : .shoreMorph }
    private var open: Bool { model.revealed }

    var body: some View {
        ZStack {
            capsule
                .opacity(open ? 1 : 0)
                .scaleEffect(open ? 1 : 0.92)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(morph, value: open)
        .animation(morph, value: model.targeted)
        .allowsHitTesting(open)
        .accessibilityElement(children: open ? .contain : .ignore)
        .accessibilityLabel("File basket")
        .accessibilityHint("Drop files to park them on the island shelf.")
    }

    private var parkedSummary: String {
        let count = shelf.items.count
        if model.targeted { return "Adds to the island shelf" }
        if count == 0 { return "Drop to park on the island" }
        if count == 1 { return "1 file on the island" }
        return "\(count) files on the island"
    }

    private var capsule: some View {
        HStack(spacing: 10) {
            Image(systemName: model.targeted ? "arrow.down.circle.fill" : "tray.and.arrow.down.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ShorePalette.seaGlass)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.targeted ? "Release to park" : "Park on Shore")
                    .font(ShoreType.title(12))
                    .foregroundStyle(ShorePalette.foam)
                    .lineLimit(1)
                Text(parkedSummary)
                    .font(ShoreType.body(10))
                    .foregroundStyle(ShorePalette.foam.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if !shelf.items.isEmpty {
                HStack(spacing: -7) {
                    ForEach(Array(shelf.items.prefix(3))) { item in
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                            .resizable()
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(ShorePalette.bezel))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.6))
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Capsule(style: .continuous)
                .fill(ShorePalette.bezel)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            ShorePalette.seaGlass.opacity(model.targeted ? 0.9 : 0.4),
                            lineWidth: model.targeted ? 1.6 : 1
                        )
                }
        }
        .padding(4)
        .onDrop(of: [UTType.fileURL], isTargeted: $model.targeted) { providers in
            FileDropCollector.collect(providers) { urls in
                shelf.add(urls: urls)
            }
            return true
        }
    }
}

#Preview("Basket") {
    let model = BasketModel()
    model.draggingFiles = true
    return BasketRootView(model: model, shelf: FileShelfStore())
        .frame(width: 260, height: 64)
        .background(Color.gray)
}
