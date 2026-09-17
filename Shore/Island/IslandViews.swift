import AppKit
import SwiftUI

@MainActor
final class IslandSession: ObservableObject {
    @Published var isExpanded = false
    @Published var isHovering = false
    @Published var hugsNotch = false
}

struct IslandRootView: View {
    @ObservedObject var session: IslandSession
    @ObservedObject var nowPlaying: NowPlayingStore
    @ObservedObject var chips: LiveChipStore
    var onToggle: () -> Void
    var onCollapse: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var islandSpace

    var body: some View {
        Group {
            if session.isExpanded {
                IslandExpandedView(
                    info: nowPlaying.info,
                    source: nowPlaying.source,
                    chips: chips.chips,
                    hugsNotch: session.hugsNotch,
                    reduceMotion: reduceMotion,
                    namespace: islandSpace,
                    onCollapse: onCollapse,
                    onTogglePlay: { nowPlaying.togglePlay() },
                    onPrevious: { nowPlaying.previous() },
                    onNext: { nowPlaying.next() }
                )
            } else {
                IslandCollapsedView(
                    info: nowPlaying.info,
                    chips: chips.chips,
                    hugsNotch: session.hugsNotch,
                    hovering: session.isHovering,
                    reduceMotion: reduceMotion,
                    namespace: islandSpace
                )
                .onTapGesture(perform: onToggle)
            }
        }
        .padding(.top, session.hugsNotch && !session.isExpanded ? 8 : 0)
        .padding(session.isExpanded ? 12 : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            IslandChrome(hugsNotch: session.hugsNotch, expanded: session.isExpanded)
        }
        .onHover { session.isHovering = $0 }
        .animation(reduceMotion ? .shoreQuiet : .shoreTide, value: session.isExpanded)
        .accessibilityElement(children: .contain)
    }
}

struct IslandCollapsedView: View {
    var info: NowPlayingInfo
    var chips: [LiveChip]
    var hugsNotch: Bool
    var hovering: Bool
    var reduceMotion: Bool
    var namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 8) {
            artwork
            if info.hasTrack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(info.title)
                        .font(ShoreType.title(11.5))
                        .foregroundStyle(ShorePalette.foam)
                        .lineLimit(1)
                    Text(info.artist)
                        .font(ShoreType.body(10))
                        .foregroundStyle(ShorePalette.foam.opacity(0.55))
                        .lineLimit(1)
                }
                TideBars(isPlaying: info.isPlaying, reduceMotion: reduceMotion)
            } else {
                Text("Shore")
                    .font(ShoreType.title(12))
                    .foregroundStyle(ShorePalette.foam.opacity(0.88))
            }
            Spacer(minLength: 4)
            ChipRow(chips: chips)
        }
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .opacity(hovering ? 1 : 0.96)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(collapsedLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Expands the Shore island")
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if let image = info.artwork {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                SampleArtwork(compact: true)
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .matchedGeometryEffect(id: "art", in: namespace)
        .accessibilityHidden(true)
    }

    private var collapsedLabel: String {
        if info.hasTrack {
            return "Now playing, \(info.title) by \(info.artist)"
        }
        return "Shore island"
    }
}

struct IslandExpandedView: View {
    var info: NowPlayingInfo
    var source: NowPlayingSource
    var chips: [LiveChip]
    var hugsNotch: Bool
    var reduceMotion: Bool
    var namespace: Namespace.ID
    var onCollapse: () -> Void
    var onTogglePlay: () -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.hasTrack ? info.title : "Nothing playing")
                        .font(ShoreType.title(15))
                        .foregroundStyle(ShorePalette.foam)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(ShoreType.body(12))
                        .foregroundStyle(ShorePalette.foam.opacity(0.58))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    progress
                }
                Button(action: onCollapse) {
                    Image(systemName: "chevron.compact.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ShorePalette.foam.opacity(0.55))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Collapse island")
            }
            HStack(spacing: 14) {
                transport
                Spacer()
                ChipRow(chips: chips)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var subtitle: String {
        if !info.hasTrack { return "Play something, or keep sample media on." }
        if source == .sample { return "\(info.artist) · sample" }
        return info.artist
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if let image = info.artwork {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                SampleArtwork(compact: false)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .matchedGeometryEffect(id: "art", in: namespace)
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
        .frame(height: 3)
        .accessibilityValue("\(Int(info.progress * 100)) percent")
    }

    private var transport: some View {
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
    IslandRootView(
        session: session,
        nowPlaying: NowPlayingStore(settings: .shared),
        chips: LiveChipStore(),
        onToggle: { session.isExpanded = true },
        onCollapse: { session.isExpanded = false }
    )
    .frame(width: 280, height: 44)
    .padding()
    .background(Color.gray)
}
