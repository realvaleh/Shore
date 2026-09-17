import AppKit
import Combine
import Darwin
import Foundation

struct NowPlayingInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var elapsed: TimeInterval
    var duration: TimeInterval
    var artwork: NSImage?

    static let sample = NowPlayingInfo(
        title: "Low Tide",
        artist: "Still Harbor",
        album: "Shore",
        isPlaying: true,
        elapsed: 73,
        duration: 214,
        artwork: nil
    )

    static let idle = NowPlayingInfo(
        title: "",
        artist: "",
        album: "",
        isPlaying: false,
        elapsed: 0,
        duration: 0,
        artwork: nil
    )

    var hasTrack: Bool { !title.isEmpty }
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }
}

enum NowPlayingSource: Equatable {
    case mediaRemote
    case sample
    case idle
}

enum MediaCommand: UInt32 {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case next = 4
    case previous = 5
}

@MainActor
final class NowPlayingStore: ObservableObject {
    @Published private(set) var info: NowPlayingInfo = .sample
    @Published private(set) var source: NowPlayingSource = .sample

    private let settings: ShoreSettings
    private let remote = MediaRemoteNowPlayingProvider()
    private var timer: Timer?
    private var lastRemote: NowPlayingInfo?
    private var lastRemoteAt = Date.distantPast
    private var cancellable: AnyCancellable?

    init(settings: ShoreSettings = .shared) {
        self.settings = settings
    }

    func start() {
        remote.start { [weak self] snapshot in
            Task { @MainActor in
                self?.lastRemote = snapshot
                self?.lastRemoteAt = Date()
                self?.publish()
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        cancellable = settings.$sampleWhenIdle
            .sink { [weak self] _ in self?.publish() }
        publish()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        remote.stop()
        cancellable = nil
    }

    func togglePlay() {
        if source == .mediaRemote {
            remote.send(.togglePlayPause)
        } else if source == .sample {
            info.isPlaying.toggle()
        }
    }

    func next() {
        if source == .mediaRemote { remote.send(.next) }
        else if source == .sample { skipSample(forward: true) }
    }

    func previous() {
        if source == .mediaRemote { remote.send(.previous) }
        else if source == .sample { skipSample(forward: false) }
    }

    private func skipSample(forward: Bool) {
        var next = info
        next.elapsed = forward ? min(next.duration, next.elapsed + 10) : max(0, next.elapsed - 10)
        info = next
    }

    private func tick() {
        if source == .mediaRemote, var live = lastRemote, live.isPlaying {
            live.elapsed = min(live.duration, live.elapsed + Date().timeIntervalSince(lastRemoteAt))
            info = live
        } else if source == .sample {
            guard info.isPlaying else { return }
            var next = info
            next.elapsed += 0.5
            if next.duration > 0, next.elapsed > next.duration { next.elapsed = 0 }
            info = next
        } else {
            publish()
        }
    }

    private func publish() {
        if let live = lastRemote, live.hasTrack {
            var displayed = live
            if live.isPlaying {
                displayed.elapsed = min(live.duration, live.elapsed + Date().timeIntervalSince(lastRemoteAt))
            }
            info = displayed
            source = .mediaRemote
        } else if settings.sampleWhenIdle {
            if source != .sample {
                info = .sample
            }
            source = .sample
        } else {
            info = .idle
            source = .idle
        }
    }
}

/// Best-effort MediaRemote client. Missing symbols or empty now-playing fall through to sample/idle.
final class MediaRemoteNowPlayingProvider {
    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
    private typealias UnregisterFn = @convention(c) () -> Void
    private typealias GetInfoFn = @convention(c) (
        DispatchQueue,
        @escaping @convention(block) (CFDictionary?) -> Void
    ) -> Void
    private typealias SendFn = @convention(c) (UInt32, CFDictionary?) -> Bool

    private let handle: UnsafeMutableRawPointer?
    private let register: RegisterFn?
    private let unregister: UnregisterFn?
    private let getInfo: GetInfoFn?
    private let sendCommand: SendFn?
    private var observer: NSObjectProtocol?
    private var handler: ((NowPlayingInfo?) -> Void)?

    var isAvailable: Bool { handle != nil && getInfo != nil }

    init() {
        handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_LAZY
        )
        func load<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle, let symbol = dlsym(handle, name) else { return nil }
            return unsafeBitCast(symbol, to: T.self)
        }
        register = load("MRMediaRemoteRegisterForNowPlayingNotifications", as: RegisterFn.self)
        unregister = load("MRMediaRemoteUnregisterForNowPlayingNotifications", as: UnregisterFn.self)
        getInfo = load("MRMediaRemoteGetNowPlayingInfo", as: GetInfoFn.self)
        sendCommand = load("MRMediaRemoteSendCommand", as: SendFn.self)
    }

    func start(handler: @escaping (NowPlayingInfo?) -> Void) {
        self.handler = handler
        guard isAvailable else {
            handler(nil)
            return
        }
        register?(DispatchQueue.main)
        observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        unregister?()
        handler = nil
    }

    func send(_ command: MediaCommand) {
        _ = sendCommand?(command.rawValue, nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.refresh()
        }
    }

    private func refresh() {
        guard let getInfo else {
            handler?(nil)
            return
        }
        getInfo(DispatchQueue.main) { [weak self] dictionary in
            self?.handler?(Self.parse(dictionary))
        }
    }

    private static func parse(_ raw: CFDictionary?) -> NowPlayingInfo? {
        guard let raw = raw as? [String: Any] else { return nil }
        let title = string(raw, "kMRMediaRemoteNowPlayingInfoTitle")
        let artist = string(raw, "kMRMediaRemoteNowPlayingInfoArtist")
        guard !title.isEmpty || !artist.isEmpty else { return nil }
        let rate = number(raw, "kMRMediaRemoteNowPlayingInfoPlaybackRate") ?? 0
        var image: NSImage?
        if let data = raw["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
            image = NSImage(data: data)
        }
        return NowPlayingInfo(
            title: title.isEmpty ? "Now Playing" : title,
            artist: artist,
            album: string(raw, "kMRMediaRemoteNowPlayingInfoAlbum"),
            isPlaying: rate > 0,
            elapsed: number(raw, "kMRMediaRemoteNowPlayingInfoElapsedTime") ?? 0,
            duration: number(raw, "kMRMediaRemoteNowPlayingInfoDuration") ?? 0,
            artwork: image
        )
    }

    private static func string(_ dict: [String: Any], _ key: String) -> String {
        dict[key] as? String ?? ""
    }

    private static func number(_ dict: [String: Any], _ key: String) -> Double? {
        (dict[key] as? NSNumber)?.doubleValue
    }
}
