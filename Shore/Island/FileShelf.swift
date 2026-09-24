import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Temporary file parking on the island. Original Shore shelf — not a clone of other tray apps.
///
/// Items are references to files the user dropped. Shore does not copy or delete them,
/// and it does not pass paths to a shell. `ParkedFilePath` canonicalizes each path and
/// refuses anything that is not a local file still inside the dropped file's directory.
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
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([Item].self, from: data) else { return }
        let accepted = stored.compactMap { item -> Item? in
            guard let canonical = ParkedFilePath.accept(storedPath: item.path) else { return nil }
            return Item(id: item.id, url: canonical)
        }
        items = accepted
        if accepted.map(\.path) != stored.map(\.path) || accepted.map(\.name) != stored.map(\.name) {
            persist()
        }
    }

    func add(urls: [URL]) {
        var next = items
        for url in urls {
            guard let canonical = ParkedFilePath.accept(url) else { continue }
            if next.contains(where: { $0.path == canonical.path }) { continue }
            next.append(Item(url: canonical))
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
        HStack(spacing: 6) {
            Image(systemName: hot ? "arrow.down.circle.fill" : (store.items.isEmpty ? "plus.circle" : "tray.fill"))
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .foregroundStyle(hot ? ShorePalette.seaGlass : ShorePalette.foam.opacity(0.82))
                .frame(width: 18, height: 18)
            if store.items.isEmpty {
                Text(hot ? "Release to park" : "Drop files to park")
                    .font(ShoreType.title(compact ? 11 : 12))
                    .foregroundStyle(ShorePalette.foam.opacity(hot ? 1 : 0.82))
                    .lineLimit(1)
                Spacer(minLength: 0)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(store.items) { item in
                            FileShelfToken(item: item) {
                                store.remove(item.id)
                            }
                        }
                    }
                }
                Button(action: { store.clear() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ShorePalette.foam.opacity(0.55))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Clear parked files")
                .accessibilityLabel("Clear parked files")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: compact ? 11 : 13, style: .continuous)
                .fill(hot ? ShorePalette.seaGlass.opacity(0.20) : Color.white.opacity(store.items.isEmpty ? 0.05 : 0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: compact ? 11 : 13, style: .continuous)
                        .strokeBorder(
                            hot ? ShorePalette.seaGlass.opacity(0.95) : Color.white.opacity(store.items.isEmpty ? 0.42 : 0.12),
                            style: StrokeStyle(
                                lineWidth: hot ? 1.5 : 1,
                                dash: (hot || !store.items.isEmpty) ? [] : [4, 3]
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
        if let url = item as? URL { return url.isFileURL ? url : nil }
        if let url = item as? NSURL {
            let value = url as URL
            return value.isFileURL ? value : nil
        }
        if let data = item as? Data {
            if let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
                return url
            }
            if let string = String(data: data, encoding: .utf8) {
                return Self.fileURL(from: string)
            }
            return nil
        }
        if let string = item as? String {
            return Self.fileURL(from: string)
        }
        return nil
    }

    /// Parse a drop payload as a file URL. Relative strings are refused so they
    /// cannot be anchored to the process working directory.
    nonisolated static func fileURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\0") else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url.isFileURL ? url : nil
        }
        guard trimmed.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: trimmed)
    }
}

/// Canonical local file URLs for the shelf.
///
/// The boundary is the directory of the path the user dropped, after that directory's
/// own symlinks are resolved. A `..` segment or a symlink that lands outside that
/// directory is refused. There is no second copy in Application Support.
enum ParkedFilePath {
    /// Restore a path from UserDefaults. Relative strings and `..` / `.` segments
    /// are refused before `URL(fileURLWithPath:)` can anchor them to the working directory.
    static func accept(storedPath: String) -> URL? {
        guard storedPath.hasPrefix("/"), !storedPath.contains("\0") else { return nil }
        let parts = storedPath.split(separator: "/")
        guard !parts.contains(where: { $0 == ".." || $0 == "." }) else { return nil }
        return accept(URL(fileURLWithPath: storedPath))
    }

    static func accept(_ url: URL) -> URL? {
        guard isLocalFile(url) else { return nil }
        guard url.path.hasPrefix("/"), url.path != "/" else { return nil }
        // Refuse traversal segments before standardization collapses them.
        guard !url.pathComponents.contains(".."), !url.pathComponents.contains(".") else { return nil }

        let lexical = url.standardizedFileURL
        guard isAbsoluteLocalFile(lexical) else { return nil }

        let resolved = lexical.resolvingSymlinksInPath().standardizedFileURL
        guard isAbsoluteLocalFile(resolved) else { return nil }

        let boundary = lexical
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard remainsInsideDroppedDirectory(resolved, directory: boundary) else { return nil }
        guard FileManager.default.fileExists(atPath: resolved.path) else { return nil }
        return resolved
    }

    private static func isLocalFile(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        if let host = url.host?.lowercased(), !host.isEmpty, host != "localhost" {
            return false
        }
        return !url.path.contains("\0")
    }

    private static func isAbsoluteLocalFile(_ url: URL) -> Bool {
        guard isLocalFile(url) else { return false }
        let path = url.path
        guard path.hasPrefix("/"), path != "/" else { return false }
        return !url.pathComponents.contains("..") && !url.pathComponents.contains(".")
    }

    /// True when `file` is the dropped path or a descendant of its directory.
    /// Prefix matching includes the trailing separator so `/Park` does not contain `/ParkEvil`.
    private static func remainsInsideDroppedDirectory(_ file: URL, directory: URL) -> Bool {
        let root = directory.standardizedFileURL.path
        let path = file.standardizedFileURL.path
        guard root.hasPrefix("/"), path.hasPrefix("/") else { return false }
        if root == "/" { return path != "/" }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix)
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
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 14, height: 14)
                Text(item.name)
                    .font(ShoreType.chip(11))
                    .foregroundStyle(ShorePalette.foam)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 76, alignment: .leading)
            }
            .contentShape(Capsule())
            .accessibilityLabel(item.name)
            .accessibilityHint("Drag out of the island to take it back")
            .onDrag {
                NSItemProvider(object: item.url as NSURL)
            } preview: {
                FileShelfDragChip(name: item.name)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(ShorePalette.foam.opacity(0.9))
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.white.opacity(0.16)))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(item.name)")
        }
        .padding(.leading, 6)
        .padding(.trailing, 1)
        .padding(.vertical, 1)
        .background {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.10))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.6)
                }
        }
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Button("Remove", action: onRemove)
        }
        .help("Drag out to take \(item.name) back, or click × to remove")
        .accessibilityElement(children: .contain)
    }
}

/// Compact drag image so pulling a token out does not snapshot the whole shelf row.
private struct FileShelfDragChip: View {
    var name: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ShorePalette.seaGlass)
            Text(name)
                .font(ShoreType.chip(11))
                .foregroundStyle(ShorePalette.foam)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous)
                .fill(ShorePalette.bezel)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(ShorePalette.seaGlass.opacity(0.85), lineWidth: 1)
                }
        }
    }
}
