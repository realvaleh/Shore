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
    /// Floating displays (no camera housing). Notched compact is housing width + `compactGrowth`.
    static let compactWidth: CGFloat = 248
    /// How far the capsule swells past the housing. Kept short so compact stays one pill.
    static let compactGrowth: CGFloat = 64
    /// Media block under the housing. The shelf, when open, is added separately.
    static let compactLip: CGFloat = 74
    static let expandedSize = CGSize(width: 368, height: 188)
    static let expandedLip: CGFloat = 208
    static let floatingGap: CGFloat = 8
    /// Parked-token band. Short enough to feel dense; tall enough for a 26pt remove target.
    static let shelfHeight: CGFloat = 44
    /// Hardware chin. Full enough to meet the camera housing, not a floating pill.
    static let restCornerRadius: CGFloat = 13
    static let compactCornerRadius: CGFloat = 22
    static let pinnedCornerRadius: CGFloat = 26
    /// 0 at rest. Open ears lengthen the shoulder; they do not paint a stem.
    static let restEarRadius: CGFloat = 0
    static let compactEarRadius: CGFloat = 18
    static let pinnedEarRadius: CGFloat = 30
    /// Straight neck covers this fraction of the camera housing before the shoulder leaves it.
    static let neckCover: CGFloat = 0.70
    /// Cubic handle as a fraction of the shoulder run. Rounder than a late snap, so the join is not a T.
    static let shoulderBend: CGFloat = 0.52
    static let shoulderRunMin: CGFloat = 20
    static let shoulderRunMax: CGFloat = 56
    /// Air between the full-width belly and the first content row.
    static let bellyContentGap: CGFloat = 8
    static let blendRadius: CGFloat = pinnedCornerRadius
    static let invertedRadius: CGFloat = pinnedEarRadius
    static let hoverSlopEnter: CGFloat = 16
    static let hoverSlopStay: CGFloat = 24
    static let notchHeightFallback: CGFloat = 32
    /// Panel extends this far above the framebuffer so the top edge's antialiasing is off-screen.
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

    /// Housing neck, one cubic shoulder, squircle chin.
    ///
    /// The neck stays at the camera width through `neckCover` of the housing so menu-bar
    /// items beside the notch stay outside the silhouette. The shoulder run scales with
    /// the ear and the wing: compact stays short, pinned gets a longer swell, and a wide
    /// body can never collapse into a diagonal or a hard T.
    /// Keep in lockstep with `scripts/island_silhouette.py`.
    static func shoulderFit(
        in rect: CGRect,
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        cornerRadius: CGFloat,
        earRadius: CGFloat
    ) -> IslandShoulderFit {
        let neck = min(max(notchWidth, 0), rect.width)
        let neckLeft = rect.midX - neck / 2
        let neckRight = neckLeft + neck
        let wing = max(0, (rect.width - neck) / 2)
        let bottomRadius = min(
            max(cornerRadius, 8),
            max(6, rect.width / 2 - 1),
            rect.height * 0.46
        )
        let housing = max(0, notchHeight)
        let yStartCap = max(8, rect.height - bottomRadius - 8)
        let yStart = rect.minY + min(max(8, housing * neckCover), yStartCap)
        let opens = wing > 1.5
        var yBelly = yStart
        if opens {
            let run = min(
                shoulderRunMax,
                max(shoulderRunMin, earRadius * 0.70 + wing * 0.34)
            )
            let target = max(yStart + run, rect.minY + housing + 4)
            yBelly = min(rect.maxY - bottomRadius - 4, target)
            if yBelly < yStart + 14 {
                yBelly = min(rect.maxY - bottomRadius - 2, yStart + 14)
            }
        }
        return IslandShoulderFit(
            neckLeft: neckLeft,
            neckRight: neckRight,
            yStart: yStart,
            yBelly: yBelly,
            bottomRadius: bottomRadius,
            opens: opens
        )
    }

    /// Top inset so media sits in the full-width belly, just under the shoulder.
    static func contentInset(
        hugsNotch: Bool,
        pinned: Bool,
        hovering: Bool,
        notch: CGSize,
        chrome: CGSize
    ) -> CGFloat {
        guard hugsNotch else { return pinned ? 16 : 10 }
        guard hovering || pinned, notch.height > 0, chrome.height > 1 else {
            return max(0, notch.height)
        }
        let fit = shoulderFit(
            in: CGRect(origin: .zero, size: chrome),
            notchWidth: notch.width,
            notchHeight: notch.height,
            cornerRadius: cornerRadius(pinned: pinned, hovering: hovering),
            earRadius: earRadius(pinned: pinned, hovering: hovering)
        )
        let inset = fit.yBelly + bellyContentGap
        return min(max(notch.height, inset), max(notch.height, chrome.height - 36))
    }
}

/// Resolved housing-neck geometry for one chrome rect. SwiftUI y-down.
struct IslandShoulderFit: Equatable {
    var neckLeft: CGFloat
    var neckRight: CGFloat
    var yStart: CGFloat
    /// Y where the side has reached the full body width.
    var yBelly: CGFloat
    var bottomRadius: CGFloat
    var opens: Bool
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

/// One continuous island silhouette that morphs rest → compact → expanded.
///
/// The top segment is the camera housing, flush with the bezel — never the full
/// body width (that paints a status-bar tab and squared corners into the menu bar).
/// When the body is wider, a single cubic shoulder with vertical tangents swells
/// from the lower housing into the belly — long enough that the join is not a T,
/// late enough that the upper housing stays neck-width. Rest (no wing) degenerates
/// to the housing: flush top, straight sides, rounded chin. Same path family at every stage.
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

    /// Housing neck on top, one cubic shoulder, squircle chin. Rest collapses the shoulder.
    private func shoulder(in rect: CGRect) -> IslandShoulderFit {
        IslandMetrics.shoulderFit(
            in: rect,
            notchWidth: notchWidth,
            notchHeight: notchHeight,
            cornerRadius: cornerRadius,
            earRadius: earRadius
        )
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
        let bend = IslandMetrics.shoulderBend
        let fit = shoulder(in: rect)
        let left = rect.minX
        let right = rect.maxX
        let bottom = rect.maxY

        // Desktop lip only — the housing edge and the shoulder stay unstroked
        // so a highlight cannot read as a seam or a hairline under the bezel.
        if !includeTop {
            guard fit.opens else { return Path() }
            var lip = Path()
            lip.move(to: CGPoint(x: right, y: fit.yBelly))
            lip.addLine(to: CGPoint(x: right, y: bottom - fit.bottomRadius))
            addCorner(
                &lip,
                from: CGPoint(x: right, y: bottom - fit.bottomRadius),
                corner: CGPoint(x: right, y: bottom),
                to: CGPoint(x: right - fit.bottomRadius, y: bottom),
                kappa: squircle
            )
            lip.addLine(to: CGPoint(x: left + fit.bottomRadius, y: bottom))
            addCorner(
                &lip,
                from: CGPoint(x: left + fit.bottomRadius, y: bottom),
                corner: CGPoint(x: left, y: bottom),
                to: CGPoint(x: left, y: bottom - fit.bottomRadius),
                kappa: squircle
            )
            lip.addLine(to: CGPoint(x: left, y: fit.yBelly))
            return lip
        }

        var path = Path()
        path.move(to: CGPoint(x: fit.neckLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: fit.neckRight, y: rect.minY))
        path.addLine(to: CGPoint(x: fit.neckRight, y: fit.yStart))
        if fit.opens {
            let dy = max(0.01, fit.yBelly - fit.yStart)
            path.addCurve(
                to: CGPoint(x: right, y: fit.yBelly),
                control1: CGPoint(x: fit.neckRight, y: fit.yStart + bend * dy),
                control2: CGPoint(x: right, y: fit.yBelly - bend * dy)
            )
        }
        path.addLine(to: CGPoint(x: right, y: bottom - fit.bottomRadius))
        addCorner(
            &path,
            from: CGPoint(x: right, y: bottom - fit.bottomRadius),
            corner: CGPoint(x: right, y: bottom),
            to: CGPoint(x: right - fit.bottomRadius, y: bottom),
            kappa: squircle
        )
        path.addLine(to: CGPoint(x: left + fit.bottomRadius, y: bottom))
        addCorner(
            &path,
            from: CGPoint(x: left + fit.bottomRadius, y: bottom),
            corner: CGPoint(x: left, y: bottom),
            to: CGPoint(x: left, y: bottom - fit.bottomRadius),
            kappa: squircle
        )
        let sideY = fit.opens ? fit.yBelly : fit.yStart
        path.addLine(to: CGPoint(x: left, y: sideY))
        if fit.opens {
            let dy = max(0.01, fit.yBelly - fit.yStart)
            path.addCurve(
                to: CGPoint(x: fit.neckLeft, y: fit.yStart),
                control1: CGPoint(x: left, y: fit.yBelly - bend * dy),
                control2: CGPoint(x: fit.neckLeft, y: fit.yStart + bend * dy)
            )
        }
        path.addLine(to: CGPoint(x: fit.neckLeft, y: rect.minY))
        path.closeSubpath()
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

struct IslandChrome<Content: View>: View {
    var hugsNotch: Bool
    var shape: IslandBlendShape
    var dropHot: Bool
    var content: Content

    init(
        hugsNotch: Bool,
        shape: IslandBlendShape,
        dropHot: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.hugsNotch = hugsNotch
        self.shape = shape
        self.dropHot = dropHot
        self.content = content()
    }

    /// Rest is the camera housing: no stroke, no shadow, so nothing reads as a gray halo.
    private var resting: Bool { hugsNotch && shape.earRadius < 1 && !dropHot }

    var body: some View {
        ZStack(alignment: .top) {
            shape.fill(ShorePalette.bezel)
            if !resting {
                NotchLipStroke(shape: shape)
                    .stroke(
                        dropHot ? ShorePalette.seaGlass.opacity(0.92) : Color.white.opacity(0.06),
                        lineWidth: dropHot ? 1.5 : 0.6
                    )
            }
            content
        }
        .clipShape(shape)
        .compositingGroup()
        .shadow(
            color: Color.black.opacity(resting ? 0 : 0.30),
            radius: resting ? 0 : 16,
            y: resting ? 0 : 9
        )
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
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(isPlaying ? ShorePalette.seaGlass.opacity(0.95) : ShorePalette.foam.opacity(0.32))
                        .frame(width: 2, height: barHeight(index: index, t: t))
                }
            }
            .frame(width: 18, height: 14, alignment: .bottom)
        }
    }

    private func barHeight(index: Int, t: TimeInterval) -> CGFloat {
        guard isPlaying, !reduceMotion else { return 3 }
        let phase = t * (1.9 + Double(index) * 0.28) + Double(index) * 0.7
        return 3 + CGFloat((sin(phase) + 1) / 2) * 11
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
                Group {
                    if looping {
                        HStack(spacing: 36) {
                            scrollingCopy
                            scrollingCopy
                        }
                        .offset(x: -travel)
                    } else {
                        Text(text)
                            .font(font)
                            .foregroundStyle(color)
                            .lineLimit(lineLimit)
                            .truncationMode(.tail)
                            .minimumScaleFactor(lineLimit > 1 ? 0.88 : 1)
                            .frame(width: geo.size.width, alignment: .leading)
                    }
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .clipped()
            .background(alignment: .leading) {
                scrollingCopy
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

    /// Full-width copy used to measure overflow and to scroll. The resting label ellipsizes instead.
    private var scrollingCopy: some View {
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
