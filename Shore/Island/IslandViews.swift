import AppKit
import SwiftUI

enum IslandStage: Equatable {
    case rest
    case compact
    case pinned
}

@MainActor
final class IslandSession: ObservableObject {
    @Published var isPinned = false
    @Published var isHovering = false
    @Published var hugsNotch = false
    @Published var notchWidth: CGFloat = 0
    @Published var notchHeight: CGFloat = 0
    /// After an explicit dismiss, hover is ignored until the pointer leaves the island.
    var hoverSuspended = false

    var isExpanded: Bool { isPinned }

    var stage: IslandStage {
        if isPinned { return .pinned }
        if isHovering { return .compact }
        return .rest
    }

    func pin() {
        hoverSuspended = false
        shoreAnimate {
            isPinned = true
            isHovering = true
        }
    }

    func collapseExplicitly() {
        hoverSuspended = true
        shoreAnimate {
            isPinned = false
            isHovering = false
        }
    }
}

struct IslandRootView: View {
    @ObservedObject var session: IslandSession
    @ObservedObject var nowPlaying: NowPlayingStore
    @ObservedObject var chips: LiveChipStore
    @ObservedObject var shelf: FileShelfStore
    @ObservedObject var settings: ShoreSettings
    var onToggle: () -> Void
    var onCollapse: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fileShelfEnabled: Bool { settings.fileShelfEnabled }
    private var stage: IslandStage { session.stage }

    private var chromeSize: CGSize {
        IslandPlacement.chromeSize(
            hovering: session.isHovering,
            pinned: session.isPinned,
            hugsNotch: session.hugsNotch,
            notch: CGSize(width: session.notchWidth, height: session.notchHeight),
            shelfVisible: fileShelfEnabled && (session.isHovering || session.isPinned)
        )
    }

    private var morph: Animation { reduceMotion ? .shoreQuiet : .shoreMorph }

    var body: some View {
        ZStack(alignment: .top) {
            IslandChrome(
                hugsNotch: session.hugsNotch,
                notchWidth: session.notchWidth,
                notchHeight: session.notchHeight,
                expanded: stage != .rest
            )
            IslandCanvas(
                stage: stage,
                hugsNotch: session.hugsNotch,
                notchHeight: session.notchHeight,
                info: nowPlaying.info,
                source: nowPlaying.source,
                chips: chips,
                shelf: shelf,
                fileShelfEnabled: fileShelfEnabled,
                reduceMotion: reduceMotion,
                onToggle: onToggle,
                onCollapse: onCollapse,
                onTogglePlay: { nowPlaying.togglePlay() },
                onPrevious: { nowPlaying.previous() },
                onNext: { nowPlaying.next() }
            )
        }
        .frame(width: chromeSize.width, height: chromeSize.height, alignment: .top)
        .mask(alignment: .top) {
            if session.hugsNotch {
                IslandBlendShape(
                    notchWidth: session.notchWidth,
                    notchHeight: session.notchHeight,
                    cornerRadius: stage == .pinned ? IslandMetrics.blendRadius : 16,
                    invertedRadius: IslandMetrics.invertedRadius
                )
            } else {
                RoundedRectangle(
                    cornerRadius: stage == .pinned ? IslandMetrics.blendRadius : 16,
                    style: .continuous
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(0)
        .ignoresSafeArea(.all)
        .animation(morph, value: stage)
        .animation(morph, value: chromeSize)
        .accessibilityElement(children: .contain)
    }
}

/// One view tree whose frames spring — never swapped with an opacity transition.
private struct IslandCanvas: View {
    var stage: IslandStage
    var hugsNotch: Bool
    var notchHeight: CGFloat
    var info: NowPlayingInfo
    var source: NowPlayingSource
    @ObservedObject var chips: LiveChipStore
    @ObservedObject var shelf: FileShelfStore
    var fileShelfEnabled: Bool
    var reduceMotion: Bool
    var onToggle: () -> Void
    var onCollapse: () -> Void
    var onTogglePlay: () -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void

    private var isPinned: Bool { stage == .pinned }
    private var showsContent: Bool { !(hugsNotch && stage == .rest) }
    private var artSize: CGFloat { isPinned ? 76 : 24 }
    private var cameraInset: CGFloat { hugsNotch ? notchHeight : 0 }
    private var extraOpen: Bool { isPinned }
    private var shelfOpen: Bool { fileShelfEnabled && stage != .rest }

    var body: some View {
        VStack(alignment: .leading, spacing: isPinned ? 10 : 6) {
            topRow
            progress
                .frame(height: extraOpen ? 3 : 0)
                .opacity(extraOpen ? 1 : 0)
            bottomRow
                .frame(height: extraOpen ? 36 : 0)
                .opacity(extraOpen ? 1 : 0)
            if fileShelfEnabled {
                FileShelfView(store: shelf, compact: !isPinned)
                    .frame(height: shelfOpen ? (isPinned ? 52 : 40) : 0)
                    .opacity(shelfOpen ? 1 : 0)
            }
        }
        .padding(.top, cameraInset)
        .padding(.horizontal, isPinned ? 16 : 12)
        .padding(.bottom, isPinned ? 12 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(showsContent ? 1 : 0)
        .accessibilityElement(children: showsContent ? .contain : .ignore)
        .accessibilityLabel(showsContent ? accessibilityLabel : "Shore island")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isPinned ? "Click outside to collapse" : "Expands the Shore island")
    }

    private var topRow: some View {
        HStack(alignment: isPinned ? .top : .center, spacing: isPinned ? 14 : 10) {
            HStack(alignment: isPinned ? .top : .center, spacing: isPinned ? 14 : 10) {
                artwork
                VStack(alignment: .leading, spacing: isPinned ? 4 : 2) {
                    ShoreMarquee(
                        text: info.hasTrack ? info.title : (isPinned ? "Nothing playing" : "Shore"),
                        font: ShoreType.title(isPinned ? 16 : 12.5),
                        color: ShorePalette.foam,
                        reduceMotion: reduceMotion || isPinned,
                        lineLimit: isPinned ? 2 : 1
                    )
                    .frame(height: isPinned ? 40 : 16)
                    Text(subtitle)
                        .font(ShoreType.body(isPinned ? 12 : 10.5))
                        .foregroundStyle(ShorePalette.foam.opacity(0.58))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .opacity(info.hasTrack || isPinned ? 1 : 0)
                        .frame(height: info.hasTrack || isPinned ? (isPinned ? 16 : 13) : 0)
                }
                .frame(maxWidth: .infinity, minHeight: isPinned ? 76 : 0, alignment: .topLeading)
                .layoutPriority(1)
                TideBars(isPlaying: info.isPlaying, reduceMotion: reduceMotion)
                    .frame(width: extraOpen ? 0 : 16)
                    .opacity(extraOpen || !info.hasTrack ? 0 : 1)
                    .clipped()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if !isPinned { onToggle() }
            }
            ChipRow(store: chips, compact: !isPinned)
            Button(action: onCollapse) {
                Image(systemName: "chevron.compact.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ShorePalette.foam.opacity(0.55))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .frame(width: extraOpen ? 22 : 0)
            .opacity(extraOpen ? 1 : 0)
            .clipped()
            .allowsHitTesting(extraOpen)
            .accessibilityLabel("Collapse island")
            .accessibilityHint("Or click outside the island")
            .accessibilityHidden(!extraOpen)
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 14) {
            HStack(spacing: 16) {
                IconButton(systemName: "backward.fill", action: onPrevious)
                    .accessibilityLabel("Back 10 seconds")
                Button(action: onTogglePlay) {
                    Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ShorePalette.ink)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(ShorePalette.foam))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(info.isPlaying ? "Pause" : "Play")
                IconButton(systemName: "forward.fill", action: onNext)
                    .accessibilityLabel("Forward 10 seconds")
            }
            Spacer(minLength: 8)
        }
        .clipped()
        .allowsHitTesting(extraOpen)
    }

    private var subtitle: String {
        if !info.hasTrack { return "Play something, or keep sample media on." }
        if source == .sample { return "\(info.artist) · sample" }
        return info.artist
    }

    private var artwork: some View {
        Group {
            if let image = info.artwork {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                SampleArtwork(compact: !isPinned)
            }
        }
        .frame(width: artSize, height: artSize)
        .clipShape(RoundedRectangle(cornerRadius: isPinned ? 14 : 6, style: .continuous))
        .accessibilityHidden(true)
    }

    private var progress: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(ShorePalette.seaGlass.opacity(0.95))
                    .frame(width: max(4, geo.size.width * info.progress))
            }
        }
        .clipped()
        .accessibilityValue("\(Int(info.progress * 100)) percent")
        .accessibilityHidden(!extraOpen)
    }

    private var accessibilityLabel: String {
        if info.hasTrack {
            return "Now playing, \(info.title) by \(info.artist)"
        }
        return "Shore island"
    }
}

private struct IconButton: View {
    var systemName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ShorePalette.foam.opacity(0.86))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Collapsed") {
    let session = IslandSession()
    session.isHovering = true
    session.hugsNotch = true
    session.notchWidth = 184
    session.notchHeight = 32
    return IslandRootView(
        session: session,
        nowPlaying: NowPlayingStore(settings: .shared),
        chips: LiveChipStore(),
        shelf: FileShelfStore(),
        settings: .shared,
        onToggle: { session.pin() },
        onCollapse: { session.collapseExplicitly() }
    )
    .frame(width: 428, height: 220)
    .padding()
    .background(Color.gray)
}
