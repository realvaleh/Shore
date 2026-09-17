import AppKit
import Combine
import SwiftUI

/// A quiet glass shoreline that sits above the Dock. Click-through — never steals Dock clicks.
@MainActor
final class DockModule {
    private let panel: OverlayPanel
    private let host: NSHostingController<TideLineView>
    private let model: TideLineModel
    private var screenObserver: NSObjectProtocol?
    private var mouseTimer: Timer?

    init() {
        let model = TideLineModel()
        self.model = model
        let screen = ScreenGeometry.primary
        let size = Self.panelSize(on: screen)
        host = NSHostingController(rootView: TideLineView(model: model))
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = NSColor.clear.cgColor
        host.view.autoresizingMask = [.width, .height]

        panel = OverlayPanel(size: size, interactive: false)
        panel.contentView = host.view
        panel.setFrame(Self.panelFrame(on: screen), display: true)
        panel.alphaValue = 0
        relayout()
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.45
            panel.animator().alphaValue = 1
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.relayout() }
        }

        mouseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.trackMouse() }
        }
        RunLoop.main.add(mouseTimer!, forMode: .common)
    }

    func invalidate() {
        mouseTimer?.invalidate()
        mouseTimer = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        panel.orderOut(nil)
        panel.close()
    }

    private func relayout() {
        let screen = ScreenGeometry.primary
        let dock = ScreenGeometry.bottomDockHeight(on: screen)
        model.visible = dock >= 22
        model.lineWidth = min(480, screen.frame.width * 0.42)
        panel.setFrame(Self.panelFrame(on: screen), display: true)
        host.view.setFrameSize(Self.panelSize(on: screen))
    }

    private func trackMouse() {
        guard model.visible else {
            model.foam = nil
            return
        }
        let screen = ScreenGeometry.primary
        let mouse = NSEvent.mouseLocation
        let dock = ScreenGeometry.bottomDockHeight(on: screen)
        let band = NSRect(
            x: screen.frame.midX - model.lineWidth / 2 - 40,
            y: screen.frame.minY,
            width: model.lineWidth + 80,
            height: dock + 56
        )
        guard band.contains(mouse) else {
            model.foam = nil
            return
        }
        let originX = screen.frame.midX - model.lineWidth / 2
        model.foam = min(1, max(0, (mouse.x - originX) / model.lineWidth))
    }

    private static func panelSize(on screen: NSScreen) -> CGSize {
        CGSize(width: screen.frame.width, height: 28)
    }

    private static func panelFrame(on screen: NSScreen) -> NSRect {
        let dock = ScreenGeometry.bottomDockHeight(on: screen)
        let size = panelSize(on: screen)
        let y = screen.frame.minY + dock + 6
        return NSRect(x: screen.frame.minX, y: y, width: size.width, height: size.height)
    }
}

@MainActor
final class TideLineModel: ObservableObject {
    @Published var visible = true
    @Published var foam: CGFloat?
    @Published var lineWidth: CGFloat = 420
}

struct TideLineView: View {
    @ObservedObject var model: TideLineModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            if model.visible {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    ShorePalette.seaGlass.opacity(0.10),
                                    Color.white.opacity(0.14),
                                    ShorePalette.seaGlass.opacity(0.10)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: model.lineWidth, height: 7)
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.6)
                        }
                        .shadow(color: ShorePalette.seaGlass.opacity(0.18), radius: 10, y: 0)

                    if let foam = model.foam {
                        Capsule(style: .continuous)
                            .fill(ShorePalette.foam.opacity(0.45))
                            .frame(width: 72, height: 6)
                            .blur(radius: reduceMotion ? 0 : 5)
                            .offset(x: (foam - 0.5) * (model.lineWidth - 72))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .opacity(model.foam == nil ? 0.72 : 0.95)
                .animation(reduceMotion ? .shoreQuiet : .shoreFoam, value: model.foam)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Tide Line") {
    TideLineView(model: TideLineModel())
        .frame(width: 640, height: 40)
        .background(Color.black)
}
