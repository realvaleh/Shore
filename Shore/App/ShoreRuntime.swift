import Combine
import Foundation

@MainActor
final class ShoreRuntime {
    private let settings = ShoreSettings.shared
    private let nowPlaying = NowPlayingStore()
    private let chips = LiveChipStore()
    private var island: IslandModule?
    private var dock: DockModule?
    private var cancellables = Set<AnyCancellable>()

    func start() {
        nowPlaying.start()
        chips.start()
        applyModules()

        settings.$islandEnabled
            .combineLatest(settings.$dockEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.applyModules()
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
                island = IslandModule(nowPlaying: nowPlaying, chips: chips)
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
