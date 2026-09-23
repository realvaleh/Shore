import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Temporary file parking on the island. Original Shore shelf — not a clone of other tray apps.
@MainActor
final class FileShelfStore: ObservableObject {
    struct Item: Identifiable, Equatable, Codable {
        var id: UUID
        var path: String
        var name: String

        var url: URL { URL(fileURLWithPath: path) }

        init(id: UUID = UUID(), url: URL) {
            self.id = id
            self.path = url.path
            self.name = url.lastPathComponent
        }
    }

    @Published private(set) var items: [Item] = []

    private let defaults: UserDefaults
    private let key = "shore.fileShelf.items"
    static let capacity = 12

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Item].self, from: data) {
            items = decoded.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    func add(urls: [URL]) {
        var next = items
        for url in urls {
            let resolved = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: resolved.path) else { continue }
            if next.contains(where: { $0.path == resolved.path }) { continue }
            next.append(Item(url: resolved))
        }
        if next.count > Self.capacity {
            next = Array(next.suffix(Self.capacity))
        }
        items = next
        persist()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}

struct FileShelfView: View {
    @ObservedObject var store: FileShelfStore
    var compact: Bool = false
    var highlighted: Bool = false
    @State private var targeted = false

    private var hot: Bool { targeted || highlighted }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: hot ? "arrow.down.circle.fill" : (store.items.isEmpty ? "plus.circle" : "tray.fill"))
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .foregroundStyle(hot ? ShorePalette.seaGlass : ShorePalette.foam.opacity(0.8))
                .frame(width: 16)
            if store.items.isEmpty {
                Text(hot ? "Release to park" : "Drop files to park")
                    .font(ShoreType.title(compact ? 11 : 12))
                    .foregroundStyle(ShorePalette.foam.opacity(hot ? 0.95 : 0.72))
                    .lineLimit(1)
                Spacer(minLength: 0)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.items) { item in
                            FileShelfToken(item: item) {
                                store.remove(item.id)
                            }
                        }
                    }
                }
                Button(action: { store.clear() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ShorePalette.foam.opacity(0.45))
                }
                .buttonStyle(.plain)
                .help("Clear parked files")
                .accessibilityLabel("Clear parked files")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, compact ? 4 : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous)
                .fill(Color.white.opacity(hot ? 0.16 : 0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous)
                        .strokeBorder(
                            hot ? ShorePalette.seaGlass.opacity(0.95) : Color.white.opacity(store.items.isEmpty ? 0.28 : 0.12),
                            style: StrokeStyle(
                                lineWidth: hot ? 1.5 : 1,
                                dash: (hot || !store.items.isEmpty) ? [] : [3, 3]
                            )
                        )
                }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            FileDropCollector.collect(providers) { urls in
                store.add(urls: urls)
            }
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(hot ? "Release to park files" : "File shelf")
        .accessibilityHint("Drop files to park them. Drag a token out to take it back.")
    }
}

enum FileDropCollector {
    static func collect(_ providers: [NSItemProvider], done: @escaping @MainActor ([URL]) -> Void) {
        let box = FileDropURLBox()
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                guard let url = Self.url(from: item) else { return }
                box.append(url)
            }
        }
        group.notify(queue: .main) {
            let urls = box.snapshot()
            Task { @MainActor in
                done(urls)
            }
        }
    }

    nonisolated static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let url = item as? NSURL { return url as URL }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let string = item as? String {
            return URL(fileURLWithPath: string.replacingOccurrences(of: "file://", with: ""))
        }
        return nil
    }
}

/// Collects drop URLs from concurrent `NSItemProvider` callbacks without capturing a mutating Array.
private final class FileDropURLBox: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }

    func snapshot() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }
}

struct FileShelfToken: View {
    var item: FileShelfStore.Item
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
            Text(item.name)
                .font(ShoreType.chip(11))
                .foregroundStyle(ShorePalette.foam)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 92, alignment: .leading)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(ShorePalette.foam.opacity(0.8))
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(item.name)")
        }
        .padding(.leading, 7)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.10))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6)
                }
        }
        .onDrag {
            NSItemProvider(object: item.url as NSURL)
        }
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Button("Remove", action: onRemove)
        }
        .help("Drag out to take \(item.name) back, or click × to remove")
        .accessibilityLabel(item.name)
        .accessibilityHint("Drag out of the island, or activate to remove")
    }
}
