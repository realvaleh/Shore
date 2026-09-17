import Combine
import Foundation

@MainActor
final class ShoreRuntime {
    private let settings: ShoreSettings
    private let nowPlaying: NowPlayingStore
    private let chips: LiveChipStore
    private let shelf: FileShelfStore
    private var island: IslandModule?
    private var dock: DockModule?
    private var cancellables = Set<AnyCancellable>()

    init() {
        let settings = ShoreSettings.shared
        self.settings = settings
        self.nowPlaying = NowPlayingStore(settings: settings)
        self.chips = LiveChipStore()
        self.shelf = FileShelfStore()
    }

    func start() {
        nowPlaying.start()
        chips.start()
        applyModules()

        settings.$islandEnabled
            .combineLatest(settings.$dockEnabled)
            .sink { [weak self] _, _ in
                Task { @MainActor in
                    self?.applyModules()
                }
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        island?.invalidate()
        island = nil
        dock?.invalidate()
        dock = nil
        nowPlaying.stop()
        chips.stop()
    }

    private func applyModules() {
        if settings.islandEnabled {
            if island == nil {
                island = IslandModule(
                    nowPlaying: nowPlaying,
                    chips: chips,
                    settings: settings,
                    shelf: shelf
                )
            }
        } else if island != nil {
            island?.invalidate()
            island = nil
        }

        if settings.dockEnabled {
            if dock == nil {
                dock = DockModule()
            }
        } else if dock != nil {
            dock?.invalidate()
            dock = nil
        }
    }
}
