import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var dropTargeted = false

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

    private var silhouette: IslandBlendShape {
        IslandBlendShape.island(
            hugsNotch: session.hugsNotch,
            notchWidth: session.notchWidth,
            notchHeight: session.notchHeight,
            pinned: session.isPinned,
            hovering: session.isHovering
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            IslandChrome(
                hugsNotch: session.hugsNotch,
                shape: silhouette
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
                dropTargeted: dropTargeted,
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
            silhouette
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(0)
        .ignoresSafeArea(.all)
        .animation(morph, value: stage)
        .animation(morph, value: chromeSize)
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            guard fileShelfEnabled else { return false }
            FileDropCollector.collect(providers) { urls in
                shelf.add(urls: urls)
            }
            return true
        }
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
    var dropTargeted: Bool
    var reduceMotion: Bool
    var onToggle: () -> Void
    var onCollapse: () -> Void
    var onTogglePlay: () -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void

    private var isPinned: Bool { stage == .pinned }
    private var showsContent: Bool { !(hugsNotch && stage == .rest) }
    private var artSize: CGFloat { isPinned ? 72 : 26 }
    private var cameraInset: CGFloat { hugsNotch ? notchHeight : 0 }
    private var extraOpen: Bool { isPinned }
    private var shelfOpen: Bool { fileShelfEnabled && stage != .rest }
    private var volumeHUD: LiveChip? {
        chips.chips.first(where: { $0.kind == .volume && $0.emphasized })
    }
    private var showHUD: Bool { !isPinned && volumeHUD != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: isPinned ? 10 : 6) {
            if showHUD, let hud = volumeHUD {
                VolumeHUDRow(chip: hud)
                    .frame(height: 28)
            } else {
                topRow
            }
            if extraOpen {
                seekRow
                    .frame(height: 16)
            }
            bottomRow
                .frame(height: extraOpen ? 36 : 0)
                .opacity(extraOpen ? 1 : 0)
            if fileShelfEnabled {
                FileShelfView(store: shelf, compact: !isPinned, highlighted: dropTargeted)
                    .frame(height: shelfOpen ? (isPinned ? 48 : 36) : 0)
                    .opacity(shelfOpen ? 1 : 0)
            }
        }
        .padding(.top, cameraInset)
        .padding(.horizontal, isPinned ? 18 : 14)
        .padding(.bottom, isPinned ? 12 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(showsContent ? 1 : 0)
        .accessibilityElement(children: showsContent ? .contain : .ignore)
        .accessibilityLabel(showsContent ? accessibilityLabel : "Shore island")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isPinned ? "Click outside to collapse" : "Expands the Shore island")
    }

    private var topRow: some View {
        HStack(alignment: isPinned ? .center : .center, spacing: isPinned ? 14 : 10) {
            artwork
            VStack(alignment: .leading, spacing: isPinned ? 3 : 1) {
                ShoreMarquee(
                    text: info.hasTrack ? info.title : (isPinned ? "Nothing playing" : "Shore"),
                    font: ShoreType.title(isPinned ? 15 : 12.5),
                    color: ShorePalette.foam,
                    reduceMotion: reduceMotion || isPinned,
                    lineLimit: 1
                )
                .frame(height: isPinned ? 20 : 16)
                Text(subtitle)
                    .font(ShoreType.body(isPinned ? 12 : 10.5))
                    .foregroundStyle(ShorePalette.foam.opacity(0.58))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .opacity(info.hasTrack || isPinned ? 1 : 0)
                    .frame(height: info.hasTrack || isPinned ? (isPinned ? 16 : 0) : 0)
            }
            .frame(maxWidth: .infinity, minHeight: isPinned ? 72 : 0, alignment: .leading)
            .layoutPriority(1)
            TideBars(isPlaying: info.isPlaying, reduceMotion: reduceMotion)
                .frame(width: extraOpen ? 0 : 16)
                .opacity(extraOpen || !info.hasTrack ? 0 : 1)
                .clipped()
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
        .contentShape(Rectangle())
        .onTapGesture {
            if !isPinned { onToggle() }
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 18) {
                IconButton(systemName: "backward.fill", action: onPrevious)
                    .accessibilityLabel("Back 10 seconds")
                Button(action: onTogglePlay) {
                    Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ShorePalette.ink)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(ShorePalette.foam))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(info.isPlaying ? "Pause" : "Play")
                IconButton(systemName: "forward.fill", action: onNext)
                    .accessibilityLabel("Forward 10 seconds")
            }
            Spacer(minLength: 8)
            ChipRow(store: chips, compact: false)
        }
        .clipped()
        .allowsHitTesting(extraOpen)
    }

    private var seekRow: some View {
        HStack(spacing: 8) {
            Text(ShoreTime.clock(info.elapsed))
                .font(ShoreType.chip(10))
                .foregroundStyle(ShorePalette.foam.opacity(0.45))
                .monospacedDigit()
                .frame(width: 34, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(ShorePalette.seaGlass.opacity(0.95))
                        .frame(width: max(4, geo.size.width * info.progress))
                }
            }
            .frame(height: 4)
            Text("-\(ShoreTime.clock(max(0, info.duration - info.elapsed)))")
                .font(ShoreType.chip(10))
                .foregroundStyle(ShorePalette.foam.opacity(0.45))
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
        .accessibilityValue("\(Int(info.progress * 100)) percent")
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
        .clipShape(RoundedRectangle(cornerRadius: isPinned ? 14 : 7, style: .continuous))
        .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        if info.hasTrack {
            return "Now playing, \(info.title) by \(info.artist)"
        }
        return "Shore island"
    }
}

private struct VolumeHUDRow: View {
    var chip: LiveChip

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: chip.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ShorePalette.foam)
                .frame(width: 22)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(ShorePalette.seaGlass)
                        .frame(width: max(6, geo.size.width * chip.progress))
                }
            }
            .frame(height: 8)
            Text(chip.label)
                .font(ShoreType.chip(11))
                .foregroundStyle(ShorePalette.foam.opacity(0.7))
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
        .accessibilityLabel("Volume \(chip.label)")
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
