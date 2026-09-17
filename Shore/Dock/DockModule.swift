import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// File cove above the Dock — drop files in, drag them out later.
/// Original Shore tray (not a reskin of other basket apps).
@MainActor
final class DockModule {
    private let panel: OverlayPanel
    private let surface: CoveSurfaceView
    private let host: NSHostingController<CoveRootView>
    private let model: CoveModel
    private let shelf: FileShelfStore
    private var screenObserver: NSObjectProtocol?
    private var mouseTimer: Timer?
    private var monitors: [Any] = []

    init(shelf: FileShelfStore) {
        let model = CoveModel()
        self.model = model
        self.shelf = shelf
        let screen = ScreenGeometry.primary
        let size = Self.panelSize(on: screen)

        host = NSHostingController(rootView: CoveRootView(model: model, shelf: shelf))
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = NSColor.clear.cgColor
        host.view.autoresizingMask = [.width, .height]

        surface = CoveSurfaceView(frame: NSRect(origin: .zero, size: size))
        surface.wantsLayer = true
        surface.layer?.backgroundColor = NSColor.clear.cgColor
        surface.addSubview(host.view)
        host.view.frame = surface.bounds
        surface.registerForDraggedTypes([.fileURL])

        panel = OverlayPanel(size: size, interactive: true)
        panel.contentView = surface
        panel.setFrame(Self.panelFrame(on: screen), display: true)
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true

        surface.chromeRectInView = { [weak self] in
            guard let self else { return .zero }
            return Self.chromeRect(in: self.surface.bounds, model: self.model, shelf: self.shelf)
        }

        relayout()
        panel.orderFrontRegardless()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Self.deliver { self?.relayout() }
        }

        mouseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            Self.deliver { self?.tick() }
        }
        RunLoop.main.add(mouseTimer!, forMode: .common)

        let dragMask: NSEvent.EventTypeMask = [.leftMouseDragged, .rightMouseDragged, .leftMouseUp]
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
        mouseTimer?.invalidate()
        mouseTimer = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        panel.orderOut(nil)
        panel.close()
    }

    private func tick() {
        let screen = ScreenGeometry.primary
        let dock = ScreenGeometry.bottomDockHeight(on: screen)
        let dragging = Self.dragPasteboardHasFiles()
        let mouse = NSEvent.mouseLocation
        let tray = Self.chromeRect(in: surface.bounds, model: model, shelf: shelf)
        let trayScreen = NSRect(
            x: panel.frame.minX + tray.minX,
            y: panel.frame.minY + tray.minY,
            width: tray.width,
            height: tray.height
        )
        let band = NSRect(
            x: trayScreen.minX - 48,
            y: screen.frame.minY,
            width: trayScreen.width + 96,
            height: dock + tray.height + 36
        )

        let wasRevealed = model.revealed
        model.dockHeight = dock
        model.dockVisible = dock >= 22
        model.draggingFiles = dragging
        model.pointerNear = band.contains(mouse)
        model.trayWidth = min(520, max(280, screen.frame.width * 0.36))

        if model.revealed != wasRevealed {
            relayout()
        } else {
            applyInteractivity()
        }
    }

    private func relayout() {
        let screen = ScreenGeometry.primary
        panel.setFrame(Self.panelFrame(on: screen), display: true)
        surface.setFrameSize(Self.panelSize(on: screen))
        host.view.setFrameSize(Self.panelSize(on: screen))
        applyInteractivity()
    }

    private func applyInteractivity() {
        let open = model.revealed
        panel.ignoresMouseEvents = !open
        if open, panel.alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                panel.animator().alphaValue = 1
            }
        } else if !open, panel.alphaValue > 0 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().alphaValue = 0
            }
        }
    }

    private static func dragPasteboardHasFiles() -> Bool {
        let pasteboard = NSPasteboard(name: .drag)
        return pasteboard.availableType(from: [.fileURL]) != nil
    }

    private static func panelSize(on screen: NSScreen) -> CGSize {
        CGSize(width: screen.frame.width, height: CoveMetrics.panelHeight)
    }

    private static func panelFrame(on screen: NSScreen) -> NSRect {
        let dock = ScreenGeometry.bottomDockHeight(on: screen)
        let size = panelSize(on: screen)
        let y = screen.frame.minY + max(dock, 8)
        return NSRect(x: screen.frame.minX, y: y, width: size.width, height: size.height)
    }

    static func chromeRect(in bounds: NSRect, model: CoveModel, shelf: FileShelfStore) -> NSRect {
        let height = CoveMetrics.trayHeight(
            dragging: model.draggingFiles || model.targeted,
            empty: shelf.items.isEmpty
        )
        return NSRect(
            x: bounds.midX - model.trayWidth / 2,
            y: CoveMetrics.bottomPad,
            width: model.trayWidth,
            height: height
        )
    }

    nonisolated private static func deliver(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            DispatchQueue.main.async { work() }
        }
    }
}

enum CoveMetrics {
    static let panelHeight: CGFloat = 120
    static let bottomPad: CGFloat = 8

    static func trayHeight(dragging: Bool, empty: Bool) -> CGFloat {
        if dragging { return 88 }
        if empty { return 44 }
        return 64
    }
}

@MainActor
final class CoveModel: ObservableObject {
    @Published var dockVisible = false
    @Published var draggingFiles = false
    @Published var pointerNear = false
    @Published var targeted = false
    @Published var dockHeight: CGFloat = 0
    @Published var trayWidth: CGFloat = 420

    var revealed: Bool { dockVisible || draggingFiles }
}

/// Hit-tests only the cove chrome so Dock icons and the desktop stay clickable.
@MainActor
final class CoveSurfaceView: NSView {
    var chromeRectInView: () -> NSRect = { .zero }

    override var isFlipped: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let chrome = chromeRectInView().insetBy(dx: -2, dy: -2)
        guard chrome.contains(point) else { return nil }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct CoveRootView: View {
    @ObservedObject var model: CoveModel
    @ObservedObject var shelf: FileShelfStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var morph: Animation { reduceMotion ? .shoreQuiet : .shoreMorph }
    private var open: Bool { model.revealed }
    private var dragging: Bool { model.draggingFiles || model.targeted }
    private var height: CGFloat {
        CoveMetrics.trayHeight(dragging: dragging, empty: shelf.items.isEmpty)
    }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            tray
                .frame(width: model.trayWidth, height: height)
                .opacity(open ? 1 : 0)
                .offset(y: open ? 0 : 18)
                .scaleEffect(open ? 1 : 0.96)
        }
        .padding(.bottom, CoveMetrics.bottomPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(morph, value: open)
        .animation(morph, value: height)
        .animation(morph, value: model.targeted)
        .animation(morph, value: shelf.items.count)
        .allowsHitTesting(open)
        .accessibilityElement(children: open ? .contain : .ignore)
        .accessibilityLabel("File cove")
        .accessibilityHint("Drop files to park them, then drag them out later.")
    }

    private var tray: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if dragging && shelf.items.isEmpty {
                Spacer(minLength: 0)
                Text("Release to park")
                    .font(ShoreType.title(13))
                    .foregroundStyle(ShorePalette.foam)
                    .frame(maxWidth: .infinity)
                Text("Files rest here until you drag them out.")
                    .font(ShoreType.body(11))
                    .foregroundStyle(ShorePalette.foam.opacity(0.55))
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else if !shelf.items.isEmpty {
                tokenRow
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, shelf.items.isEmpty && !dragging ? 0 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: dragging ? 22 : 16, style: .continuous))
        .background { trayChrome }
        .onDrop(of: [UTType.fileURL], isTargeted: $model.targeted) { providers in
            FileDropCollector.collect(providers) { urls in
                shelf.add(urls: urls)
            }
            return true
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: dragging ? "tray.and.arrow.down.fill" : "tray")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ShorePalette.seaGlass)
            Text(headerTitle)
                .font(ShoreType.chip(11))
                .foregroundStyle(ShorePalette.foam.opacity(0.82))
            Spacer(minLength: 8)
            if !shelf.items.isEmpty {
                Text("\(shelf.items.count)")
                    .font(ShoreType.chip(10))
                    .foregroundStyle(ShorePalette.foam.opacity(0.45))
                    .monospacedDigit()
                Button("Clear") { shelf.clear() }
                    .buttonStyle(.plain)
                    .font(ShoreType.chip(10))
                    .foregroundStyle(ShorePalette.foam.opacity(0.55))
            }
        }
        .padding(.top, shelf.items.isEmpty && !dragging ? 12 : 0)
    }

    private var headerTitle: String {
        if dragging { return "Cove" }
        if shelf.items.isEmpty { return "Drop files to park them" }
        return "Cove"
    }

    private var tokenRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(shelf.items) { item in
                    FileShelfToken(item: item) {
                        shelf.remove(item.id)
                    }
                }
            }
        }
        .frame(height: 34)
    }

    private var trayChrome: some View {
        RoundedRectangle(cornerRadius: dragging ? 22 : 16, style: .continuous)
            .fill(ShorePalette.bezel)
            .overlay {
                RoundedRectangle(cornerRadius: dragging ? 22 : 16, style: .continuous)
                    .strokeBorder(
                        ShorePalette.seaGlass.opacity(dragging ? 0.70 : (model.pointerNear ? 0.38 : 0.22)),
                        style: StrokeStyle(lineWidth: dragging ? 1.4 : 1, dash: shelf.items.isEmpty && !dragging ? [5, 4] : [])
                    )
            }
            .shadow(color: ShorePalette.bezel.opacity(0.35), radius: 12, y: 4)
    }
}

#Preview("Cove") {
    let model = CoveModel()
    model.dockVisible = true
    return CoveRootView(model: model, shelf: FileShelfStore())
        .frame(width: 720, height: 140)
        .background(Color.gray)
}
