import SwiftUI

enum ShorePalette {
    static let ink = Color(red: 0.047, green: 0.055, blue: 0.063)
    static let inkLift = Color(red: 0.086, green: 0.102, blue: 0.118)
    static let foam = Color(red: 0.910, green: 0.933, blue: 0.941)
    static let seaGlass = Color(red: 0.486, green: 0.620, blue: 0.627)
    static let kelp = Color(red: 0.239, green: 0.353, blue: 0.329)
    static let sand = Color(red: 0.769, green: 0.722, blue: 0.647)
    /// Same black as the MacBook camera housing / bezel.
    static let bezel = Color.black
}

enum IslandMetrics {
    static let collapsedHeight: CGFloat = 36
    static let collapsedMinWidth: CGFloat = 220
    static let compactWidth: CGFloat = 348
    static let compactLip: CGFloat = 50
    static let expandedSize = CGSize(width: 428, height: 176)
    static let expandedLip: CGFloat = 168
    static let floatingGap: CGFloat = 8
    static let shelfHeight: CGFloat = 58
    static let blendRadius: CGFloat = 22
    static let invertedRadius: CGFloat = 11
    static let hoverSlopEnter: CGFloat = 16
    static let hoverSlopStay: CGFloat = 24
    static let notchHeightFallback: CGFloat = 32
}

extension Animation {
    /// Hover expand — snappy spring, a little overshoot, not a 0.4s ease.
    static let shoreSpring = Animation.spring(response: 0.22, dampingFraction: 0.78)
    static let shoreFoam = Animation.easeInOut(duration: 0.18)
    static let shoreQuiet = Animation.easeOut(duration: 0.12)
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

/// Chrome that grows out of a hardware notch.
/// Square against the camera housing; concave shoulders where the lip meets the notch;
/// rounded only on the edge that faces the desktop.
struct IslandBlendShape: InsettableShape {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var cornerRadius: CGFloat
    var invertedRadius: CGFloat
    var insetAmount: CGFloat = 0

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(notchWidth, notchHeight),
                AnimatablePair(cornerRadius, invertedRadius)
            )
        }
        set {
            notchWidth = newValue.first.first
            notchHeight = newValue.first.second
            cornerRadius = newValue.second.first
            invertedRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        lipPath(in: rect, includeNotchTop: true)
    }

    /// Stroke the lip only — skipping the housing edge so a highlight cannot read as a seam.
    func lipStrokePath(in rect: CGRect) -> Path {
        lipPath(in: rect, includeNotchTop: false)
    }

    func inset(by amount: CGFloat) -> IslandBlendShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    private func lipPath(in rect: CGRect, includeNotchTop: Bool) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard rect.width > 1, rect.height > 1 else { return Path() }

        let nW = min(max(0, notchWidth), rect.width)
        let nH = min(max(0, notchHeight), rect.height)
        let nL = rect.minX + (rect.width - nW) / 2
        let nR = nL + nW
        let wing = max(0, (rect.width - nW) / 2)
        let lip = max(0, rect.height - nH)
        let ir = min(invertedRadius, wing * 0.55, lip * 0.45)
        let r = min(cornerRadius, rect.width / 2, max(lip, rect.height) / 2)

        var path = Path()

        if wing < 0.75 || lip < 0.75 {
            if includeNotchTop {
                path.addRect(rect)
            } else {
                path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            }
            return path
        }

        if includeNotchTop {
            path.move(to: CGPoint(x: nL, y: rect.minY))
            path.addLine(to: CGPoint(x: nR, y: rect.minY))
        } else {
            path.move(to: CGPoint(x: nR, y: rect.minY))
        }

        path.addLine(to: CGPoint(x: nR, y: nH - ir))
        path.addQuadCurve(
            to: CGPoint(x: nR + ir, y: nH),
            control: CGPoint(x: nR, y: nH)
        )
        path.addLine(to: CGPoint(x: rect.maxX - r, y: nH))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: nH + r),
            control: CGPoint(x: rect.maxX, y: nH)
        )
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
        path.addLine(to: CGPoint(x: rect.minX, y: nH + r))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + r, y: nH),
            control: CGPoint(x: rect.minX, y: nH)
        )
        path.addLine(to: CGPoint(x: nL - ir, y: nH))
        path.addQuadCurve(
            to: CGPoint(x: nL, y: nH - ir),
            control: CGPoint(x: nL, y: nH)
        )
        path.addLine(to: CGPoint(x: nL, y: rect.minY))
        if includeNotchTop {
            path.closeSubpath()
        }
        return path
    }
}

struct IslandChrome: View {
    var hugsNotch: Bool
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var expanded: Bool

    private var radius: CGFloat { expanded ? IslandMetrics.blendRadius : 16 }

    var body: some View {
        Group {
            if hugsNotch {
                bezelFill
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
            color: .black.opacity(hugsNotch ? 0 : 0.32),
            radius: hugsNotch ? 0 : 20,
            y: hugsNotch ? 0 : 10
        )
    }

    private var bezelFill: some View {
        IslandBlendShape(
            notchWidth: notchWidth,
            notchHeight: notchHeight,
            cornerRadius: radius,
            invertedRadius: IslandMetrics.invertedRadius
        )
        .fill(
            LinearGradient(
                colors: [
                    ShorePalette.bezel,
                    ShorePalette.bezel,
                    ShorePalette.ink.opacity(0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    @ViewBuilder
    private var edgeLight: some View {
        let gradient = LinearGradient(
            colors: [
                Color.white.opacity(hugsNotch ? 0.08 : 0.20),
                Color.white.opacity(0.04),
                ShorePalette.seaGlass.opacity(0.22)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        if hugsNotch {
            NotchLipStroke(
                notchWidth: notchWidth,
                notchHeight: notchHeight,
                cornerRadius: radius,
                invertedRadius: IslandMetrics.invertedRadius
            )
            .stroke(gradient, lineWidth: 0.8)
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(gradient, lineWidth: 0.8)
        }
    }
}

/// Stroke that follows IslandBlendShape but never draws the housing edge.
private struct NotchLipStroke: Shape {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var cornerRadius: CGFloat
    var invertedRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        IslandBlendShape(
            notchWidth: notchWidth,
            notchHeight: notchHeight,
            cornerRadius: cornerRadius,
            invertedRadius: invertedRadius
        )
        .lipStrokePath(in: rect)
    }
}

struct SampleArtwork: View {
    var compact: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: compact ? 6 : 12, style: .continuous)
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

/// Horizontal marquee for titles that would otherwise clip into “Still Mar…”.
struct ShoreMarquee: View {
    var text: String
    var font: Font
    var color: Color
    var reduceMotion: Bool
    var speed: CGFloat = 26

    @State private var textWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let overflow = textWidth - geo.size.width
            let looping = overflow > 6 && !reduceMotion
            TimelineView(.animation(minimumInterval: looping ? 1 / 30 : 8, paused: !looping)) { timeline in
                let travel = looping ? marqueeTravel(overflow: overflow, at: timeline.date) : 0
                HStack(spacing: 36) {
                    labeled
                    if looping { labeled }
                }
                .offset(x: -travel)
            }
            .frame(width: geo.size.width, alignment: .leading)
            .clipped()
            .background(alignment: .leading) {
                labeled
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        GeometryReader { textGeo in
                            Color.clear.preference(key: MarqueeWidthKey.self, value: textGeo.size.width)
                        }
                    )
                    .hidden()
            }
            .onPreferenceChange(MarqueeWidthKey.self) { textWidth = $0 }
            .accessibilityHidden(true)
        }
        .accessibilityElement()
        .accessibilityLabel(text)
    }

    private var labeled: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func marqueeTravel(overflow: CGFloat, at date: Date) -> CGFloat {
        let loop = overflow + 36
        guard loop > 0 else { return 0 }
        let period = Double(loop / max(speed, 8)) + 1.6
        let t = date.timeIntervalSinceReferenceDate
        let phase = t.truncatingRemainder(dividingBy: period)
        let delay = 0.9
        if phase < delay { return 0 }
        let progress = min(1, (phase - delay) / max(0.01, period - delay - 0.4))
        return CGFloat(progress) * loop
    }
}

private struct MarqueeWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
