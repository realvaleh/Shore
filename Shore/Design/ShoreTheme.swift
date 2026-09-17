import SwiftUI

enum ShorePalette {
    static let ink = Color(red: 0.047, green: 0.055, blue: 0.063)
    static let inkLift = Color(red: 0.086, green: 0.102, blue: 0.118)
    static let foam = Color(red: 0.910, green: 0.933, blue: 0.941)
    static let seaGlass = Color(red: 0.486, green: 0.620, blue: 0.627)
    static let kelp = Color(red: 0.239, green: 0.353, blue: 0.329)
    static let sand = Color(red: 0.769, green: 0.722, blue: 0.647)
}

enum IslandMetrics {
    static let collapsedHeight: CGFloat = 36
    static let collapsedMinWidth: CGFloat = 208
    static let expandedSize = CGSize(width: 336, height: 158)
    static let floatingGap: CGFloat = 8
    static let notchSideLip: CGFloat = 10
}

extension Animation {
    /// Slow water — expand/collapse. Not a cartoon spring.
    static let shoreTide = Animation.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.42)
    static let shoreFoam = Animation.easeInOut(duration: 0.22)
    static let shoreQuiet = Animation.easeOut(duration: 0.16)
}

enum ShoreType {
    static func title(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    static func body(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .regular, design: .rounded)
    }

    static func chip(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }
}

/// Square against the camera housing, rounded where the island meets the desktop.
struct NotchHugShape: InsettableShape {
    var bottomRadius: CGFloat = 18
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let r = min(bottomRadius, rect.height / 2, rect.width / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> NotchHugShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

struct IslandChrome: View {
    var hugsNotch: Bool
    var expanded: Bool

    private var radius: CGFloat { expanded ? 26 : 18 }

    var body: some View {
        Group {
            if hugsNotch {
                NotchHugShape(bottomRadius: radius)
                    .fill(ShorePalette.ink)
            } else {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(ShorePalette.ink.opacity(0.78))
                    }
            }
        }
        .overlay { edgeLight }
        .shadow(
            color: .black.opacity(hugsNotch ? 0.14 : 0.32),
            radius: hugsNotch ? 10 : 20,
            y: hugsNotch ? 3 : 10
        )
    }

    private var edgeLight: some View {
        let gradient = LinearGradient(
            colors: [
                Color.white.opacity(0.20),
                Color.white.opacity(0.04),
                ShorePalette.seaGlass.opacity(0.22)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        return Group {
            if hugsNotch {
                NotchHugShape(bottomRadius: radius)
                    .strokeBorder(gradient, lineWidth: 0.8)
            } else {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(gradient, lineWidth: 0.8)
            }
        }
    }
}

struct SampleArtwork: View {
    var compact: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: compact ? 5 : 10, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [ShorePalette.kelp, ShorePalette.seaGlass.opacity(0.85), ShorePalette.inkLift],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "water.waves")
                    .font(.system(size: compact ? 9 : 22, weight: .medium))
                    .foregroundStyle(ShorePalette.foam.opacity(0.88))
            }
    }
}

struct TideBars: View {
    var isPlaying: Bool
    var reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion || !isPlaying ? 10 : 0.11, paused: reduceMotion || !isPlaying)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(ShorePalette.foam.opacity(isPlaying ? 0.92 : 0.35))
                        .frame(width: 2, height: barHeight(index: index, t: t))
                }
            }
            .frame(height: 12, alignment: .bottom)
        }
    }

    private func barHeight(index: Int, t: TimeInterval) -> CGFloat {
        guard isPlaying, !reduceMotion else { return 4 }
        let phase = t * (2.1 + Double(index) * 0.35) + Double(index)
        return 4 + CGFloat((sin(phase) + 1) / 2) * 8
    }
}
