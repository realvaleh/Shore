import AppKit
import SwiftUI

enum ShorePalette {
    static let ink = Color(red: 0.047, green: 0.055, blue: 0.063)
    static let inkLift = Color(red: 0.086, green: 0.102, blue: 0.118)
    static let foam = Color(red: 0.910, green: 0.933, blue: 0.941)
    static let seaGlass = Color(red: 0.486, green: 0.620, blue: 0.627)
    static let kelp = Color(red: 0.239, green: 0.353, blue: 0.329)
    static let sand = Color(red: 0.769, green: 0.722, blue: 0.647)
    /// Hardware camera housing — true `#000000`, not a gray material.
    static let bezel = Color(red: 0, green: 0, blue: 0)
}

enum IslandMetrics {
    static let collapsedHeight: CGFloat = 36
    static let collapsedMinWidth: CGFloat = 220
    /// Compact is a modest capsule, not a menu-bar-wide status strip.
    static let compactWidth: CGFloat = 286
    /// One media row under the camera housing — height grows down, width grows with the top.
    static let compactLip: CGFloat = 44
    static let expandedSize = CGSize(width: 392, height: 168)
    static let expandedLip: CGFloat = 144
    static let floatingGap: CGFloat = 8
    static let shelfHeight: CGFloat = 52
    static let restCornerRadius: CGFloat = 14
    static let compactCornerRadius: CGFloat = 22
    static let pinnedCornerRadius: CGFloat = 24
    /// Rest covers the housing with square-against-bezel top; ears grow only when the body is wider.
    static let restEarRadius: CGFloat = 0
    static let compactEarRadius: CGFloat = 12
    static let pinnedEarRadius: CGFloat = 11
    static let blendRadius: CGFloat = pinnedCornerRadius
    static let invertedRadius: CGFloat = pinnedEarRadius
    static let hoverSlopEnter: CGFloat = 16
    static let hoverSlopStay: CGFloat = 24
    static let notchHeightFallback: CGFloat = 32
    static let bezelFlushNudge: CGFloat = 1

    static func cornerRadius(pinned: Bool, hovering: Bool) -> CGFloat {
        if pinned { return pinnedCornerRadius }
        if hovering { return compactCornerRadius }
        return restCornerRadius
    }

    static func earRadius(pinned: Bool, hovering: Bool) -> CGFloat {
        if pinned { return pinnedEarRadius }
        if hovering { return compactEarRadius }
        return restEarRadius
    }
}

extension Animation {
    /// Snappy spring morph — same physics for expand and collapse (not a cross-fade).
    static let shoreMorph = Animation.spring(response: 0.26, dampingFraction: 0.68)
    static let shoreSpring = shoreMorph
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

/// One continuous island silhouette that morphs collapsed → compact → expanded.
///
/// Hardware-extension family (not a T): the chrome rect *is* the island. The top
/// edge is always the full width, flush to the bezel. Concave cubic ears inset
/// the sides from those top corners so the shape melts into the menu bar; the
/// bottom is a squircle capsule. Rest (ear → 0) is square against the bezel with
/// a rounded bottom, covering the camera housing. Compact and pinned grow the
/// same path — never a narrow notch-width stem flaring into a wider body.
struct IslandBlendShape: InsettableShape {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var cornerRadius: CGFloat
    var earRadius: CGFloat
    var flushTop: Bool
    var insetAmount: CGFloat = 0

    /// Alias used by older metrics; ears are `earRadius`.
    var invertedRadius: CGFloat {
        get { earRadius }
        set { earRadius = newValue }
    }

    static func island(
        hugsNotch: Bool,
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        pinned: Bool,
        hovering: Bool
    ) -> IslandBlendShape {
        IslandBlendShape(
            notchWidth: hugsNotch ? notchWidth : 0,
            notchHeight: hugsNotch ? notchHeight : 0,
            cornerRadius: IslandMetrics.cornerRadius(pinned: pinned, hovering: hovering),
            earRadius: IslandMetrics.earRadius(pinned: pinned, hovering: hovering),
            flushTop: hugsNotch
        )
    }

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(notchWidth, notchHeight),
                AnimatablePair(cornerRadius, earRadius)
            )
        }
        set {
            notchWidth = newValue.first.first
            notchHeight = newValue.first.second
            cornerRadius = newValue.second.first
            earRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        silhouettePath(in: rect, includeTop: true)
    }

    /// Stroke the desktop lip only — skipping the housing edge so a highlight cannot read as a seam.
    func lipStrokePath(in rect: CGRect) -> Path {
        silhouettePath(in: rect, includeTop: false)
    }

    func inset(by amount: CGFloat) -> IslandBlendShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    /// AppKit (y-up) point vs chrome rect in the same view. Path math is SwiftUI y-down.
    func contains(viewPoint: CGPoint, chromeRect: CGRect) -> Bool {
        guard chromeRect.width > 1, chromeRect.height > 1, chromeRect.contains(viewPoint) else {
            return false
        }
        let local = CGPoint(
            x: viewPoint.x - chromeRect.minX,
            y: chromeRect.maxY - viewPoint.y
        )
        return path(in: CGRect(origin: .zero, size: chromeRect.size)).contains(local)
    }

    private func silhouettePath(in rect: CGRect, includeTop: Bool) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard rect.width > 1, rect.height > 1 else { return Path() }

        // Floating displays: one continuous pill, all four corners rounded.
        if !flushTop {
            return roundedRectPath(in: rect, includeTop: includeTop)
        }

        // Cubic kappa is Shore's squircle language (not a circular quad).
        let squircle: CGFloat = 0.55
        let earK: CGFloat = 0.52

        // Ears inset the vertical sides. Zero ear = square top against the bezel.
        let ear = min(max(0, earRadius), rect.width * 0.20, rect.height * 0.38)
        let sideInset = ear
        let left = rect.minX + sideInset
        let right = rect.maxX - sideInset

        let restLike = rect.height <= (notchHeight > 1 ? notchHeight + 3 : 40)
        let bottomCap = restLike ? max(cornerRadius, rect.height * 0.42) : cornerRadius
        let bottomR = min(
            max(bottomCap, 8),
            max(6, (rect.width / 2) - sideInset - 1),
            max(6, rect.height - ear - 2),
            rect.height * 0.5
        )

        var path = Path()
        if includeTop {
            // Full-width flush top — the island is as wide at the bezel as it is below.
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        }

        if ear > 0.5 {
            path.addCurve(
                to: CGPoint(x: right, y: rect.minY + ear),
                control1: CGPoint(x: rect.maxX - ear * earK, y: rect.minY),
                control2: CGPoint(x: right, y: rect.minY + ear * (1 - earK))
            )
        }

        path.addLine(to: CGPoint(x: right, y: rect.maxY - bottomR))
        addCorner(
            &path,
            from: CGPoint(x: right, y: rect.maxY - bottomR),
            corner: CGPoint(x: right, y: rect.maxY),
            to: CGPoint(x: right - bottomR, y: rect.maxY),
            kappa: squircle
        )
        path.addLine(to: CGPoint(x: left + bottomR, y: rect.maxY))
        addCorner(
            &path,
            from: CGPoint(x: left + bottomR, y: rect.maxY),
            corner: CGPoint(x: left, y: rect.maxY),
            to: CGPoint(x: left, y: rect.maxY - bottomR),
            kappa: squircle
        )
        path.addLine(to: CGPoint(x: left, y: rect.minY + ear))

        if ear > 0.5 {
            path.addCurve(
                to: CGPoint(x: rect.minX, y: rect.minY),
                control1: CGPoint(x: left, y: rect.minY + ear * (1 - earK)),
                control2: CGPoint(x: rect.minX + ear * earK, y: rect.minY)
            )
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }

        if includeTop { path.closeSubpath() }
        return path
    }

    private func roundedRectPath(in rect: CGRect, includeTop: Bool) -> Path {
        let r = min(max(cornerRadius, min(rect.height, rect.width) * 0.36), rect.width / 2, rect.height / 2)
        let k: CGFloat = 0.62
        var path = Path()
        if includeTop {
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            addCorner(
                &path,
                from: CGPoint(x: rect.maxX - r, y: rect.minY),
                corner: CGPoint(x: rect.maxX, y: rect.minY),
                to: CGPoint(x: rect.maxX, y: rect.minY + r),
                kappa: k
            )
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY + r))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        addCorner(
            &path,
            from: CGPoint(x: rect.maxX, y: rect.maxY - r),
            corner: CGPoint(x: rect.maxX, y: rect.maxY),
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            kappa: k
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        addCorner(
            &path,
            from: CGPoint(x: rect.minX + r, y: rect.maxY),
            corner: CGPoint(x: rect.minX, y: rect.maxY),
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            kappa: k
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        if includeTop {
            addCorner(
                &path,
                from: CGPoint(x: rect.minX, y: rect.minY + r),
                corner: CGPoint(x: rect.minX, y: rect.minY),
                to: CGPoint(x: rect.minX + r, y: rect.minY),
                kappa: k
            )
            path.closeSubpath()
        }
        return path
    }

    private func addCorner(
        _ path: inout Path,
        from start: CGPoint,
        corner: CGPoint,
        to end: CGPoint,
        kappa: CGFloat
    ) {
        path.addCurve(
            to: end,
            control1: CGPoint(
                x: start.x + (corner.x - start.x) * kappa,
                y: start.y + (corner.y - start.y) * kappa
            ),
            control2: CGPoint(
                x: end.x + (corner.x - end.x) * kappa,
                y: end.y + (corner.y - end.y) * kappa
            )
        )
    }
}

struct IslandChrome: View {
    var hugsNotch: Bool
    var shape: IslandBlendShape

    var body: some View {
        shape
            .fill(ShorePalette.bezel)
            .overlay { edgeLight }
            .compositingGroup()
            .shadow(
                color: ShorePalette.bezel.opacity(hugsNotch ? 0 : 0.45),
                radius: hugsNotch ? 0 : 16,
                y: hugsNotch ? 0 : 8
            )
    }

    @ViewBuilder
    private var edgeLight: some View {
        // Hairline on the desktop lip only. Rest (ear ≈ 0) draws no stroke so
        // the housing blend stays #000000 without an AA fringe at the bezel.
        let rest = hugsNotch && shape.earRadius < 1
        if !rest {
            NotchLipStroke(shape: shape)
                .stroke(Color.white.opacity(hugsNotch ? 0.04 : 0.06), lineWidth: 0.5)
        }
    }
}

enum ShoreTime {
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// Stroke that follows IslandBlendShape but never draws the housing edge.
private struct NotchLipStroke: Shape {
    var shape: IslandBlendShape

    var animatableData: IslandBlendShape.AnimatableData {
        get { shape.animatableData }
        set { shape.animatableData = newValue }
    }

    func path(in rect: CGRect) -> Path {
        shape.lipStrokePath(in: rect)
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
    var lineLimit: Int = 1

    @State private var textWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let overflow = textWidth - geo.size.width
            let looping = overflow > 6 && !reduceMotion && lineLimit == 1
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
            .lineLimit(lineLimit)
            .minimumScaleFactor(lineLimit > 1 ? 0.88 : 1)
            .fixedSize(horizontal: lineLimit == 1, vertical: false)
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
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

@MainActor
func shoreAnimate(_ updates: () -> Void) {
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        withAnimation(.shoreQuiet, updates)
    } else {
        withAnimation(.shoreMorph, updates)
    }
}
