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
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "tray")
                    .font(.system(size: 9, weight: .semibold))
                Text(store.items.isEmpty ? "Drop files to park them" : "Shelf")
                    .font(ShoreType.chip(10))
                Spacer(minLength: 4)
                if !store.items.isEmpty {
                    Button("Clear") { store.clear() }
                        .buttonStyle(.plain)
                        .font(ShoreType.chip(10))
                        .foregroundStyle(ShorePalette.foam.opacity(0.55))
                }
            }
            .foregroundStyle(ShorePalette.foam.opacity(0.62))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.items) { item in
                        FileShelfToken(item: item) {
                            store.remove(item.id)
                        }
                    }
                }
            }
            .frame(height: compact ? 28 : 34)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(targeted ? 0.10 : 0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            ShorePalette.seaGlass.opacity(targeted ? 0.55 : 0.18),
                            style: StrokeStyle(lineWidth: 1, dash: store.items.isEmpty ? [4, 3] : [])
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
        .accessibilityLabel("File shelf")
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
                .font(ShoreType.chip(10.5))
                .foregroundStyle(ShorePalette.foam)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 96, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
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
        .help(item.path)
        .accessibilityLabel(item.name)
    }
}
