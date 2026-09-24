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
    /// True while a file drag is inside the island's hover zone.
    @Published var acceptingFiles = false

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
        IslandChrome(
            hugsNotch: session.hugsNotch,
            shape: silhouette,
            dropHot: dropTargeted || session.acceptingFiles
        ) {
            IslandCanvas(
                stage: stage,
                hugsNotch: session.hugsNotch,
                notchWidth: session.notchWidth,
                notchHeight: session.notchHeight,
                chromeSize: chromeSize,
                info: nowPlaying.info,
                source: nowPlaying.source,
                chips: chips,
                shelf: shelf,
                fileShelfEnabled: fileShelfEnabled,
                dropTargeted: dropTargeted || session.acceptingFiles,
                reduceMotion: reduceMotion,
                onToggle: onToggle,
                onCollapse: onCollapse,
                onTogglePlay: { nowPlaying.togglePlay() },
                onPrevious: { nowPlaying.previous() },
                onNext: { nowPlaying.next() }
            )
        }
        .frame(width: chromeSize.width, height: chromeSize.height, alignment: .top)
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
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var chromeSize: CGSize
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
    private var artSize: CGFloat { isPinned ? 64 : 28 }
    private var artRadius: CGFloat { isPinned ? 14 : 8 }
    /// Same shoulder fit as the silhouette, so the row sits in the belly instead of the curve.
    private var contentTop: CGFloat {
        IslandMetrics.contentInset(
            hugsNotch: hugsNotch,
            pinned: isPinned,
            hovering: stage != .rest,
            notch: CGSize(width: notchWidth, height: notchHeight),
            chrome: chromeSize
        )
    }
    private var shelfOpen: Bool { fileShelfEnabled && stage != .rest }
    private var volumeHUD: LiveChip? {
        chips.chips.first(where: { $0.kind == .volume && $0.emphasized })
    }
    private var showHUD: Bool { !isPinned && volumeHUD != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showHUD, let hud = volumeHUD {
                VolumeHUDRow(chip: hud)
                    .frame(height: 28)
            } else if isPinned {
                pinnedPlayer
            } else {
                compactRow
            }
            if fileShelfEnabled {
                FileShelfView(store: shelf, compact: !isPinned, highlighted: dropTargeted)
                    .frame(height: shelfOpen ? IslandMetrics.shelfHeight : 0)
                    .clipped()
                    .opacity(shelfOpen ? 1 : 0)
                    .padding(.top, shelfOpen ? 4 : 0)
            }
        }
        .padding(.top, contentTop)
        .padding(.horizontal, isPinned ? 18 : 16)
        .padding(.bottom, isPinned ? 12 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .topTrailing) { collapseButton }
        .opacity(showsContent ? 1 : 0)
        .accessibilityElement(children: showsContent ? .contain : .ignore)
        .accessibilityLabel(showsContent ? accessibilityLabel : "Shore island")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isPinned ? "Click outside to collapse" : "Expands the Shore island")
    }

    /// One capsule row: art, title, waveform. Chips never share this row.
    private var compactRow: some View {
        HStack(spacing: 10) {
            artwork
            ShoreMarquee(
                text: info.hasTrack ? info.title : "Shore",
                font: ShoreType.title(12.5),
                color: ShorePalette.foam,
                reduceMotion: reduceMotion,
                lineLimit: 1
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 18)
            .layoutPriority(1)
            TideBars(isPlaying: info.isPlaying, reduceMotion: reduceMotion)
                .opacity(info.hasTrack ? 1 : 0.4)
        }
        .frame(height: 32)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }

    /// Player under the housing. Title column is alone; chips live on the transport row.
    private var pinnedPlayer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    ShoreMarquee(
                        text: info.hasTrack ? info.title : "Nothing playing",
                        font: ShoreType.title(16),
                        color: ShorePalette.foam,
                        reduceMotion: reduceMotion,
                        lineLimit: 1
                    )
                    .frame(height: 20)
                    Text(subtitle)
                        .font(ShoreType.body(12))
                        .foregroundStyle(ShorePalette.foam.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                .padding(.trailing, 32)
            }
            seekRow
                .frame(height: 16)
            HStack(alignment: .center, spacing: 0) {
                HStack(spacing: 14) {
                    IconButton(systemName: "backward.fill", action: onPrevious)
                        .accessibilityLabel("Back 10 seconds")
                    Button(action: onTogglePlay) {
                        Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(ShorePalette.ink)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(ShorePalette.foam))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(info.isPlaying ? "Pause" : "Play")
                    IconButton(systemName: "forward.fill", action: onNext)
                        .accessibilityLabel("Forward 10 seconds")
                }
                Spacer(minLength: 16)
                ChipRow(store: chips, compact: false)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    @ViewBuilder
    private var collapseButton: some View {
        if isPinned {
            Button(action: onCollapse) {
                Image(systemName: "chevron.compact.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ShorePalette.foam.opacity(0.62))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, contentTop - 2)
            .padding(.trailing, 10)
            .accessibilityLabel("Collapse island")
            .accessibilityHint("Or click outside the island")
        }
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
                        .fill(Color.white.opacity(0.14))
                    Capsule()
                        .fill(ShorePalette.seaGlass.opacity(0.95))
                        .frame(width: max(4, geo.size.width * info.progress))
                }
            }
            .frame(height: 5)
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
        .clipShape(RoundedRectangle(cornerRadius: artRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: artRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(isPinned ? 0.18 : 0.12), lineWidth: 0.7)
        }
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ShorePalette.foam.opacity(0.9))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
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
