import Combine
import SwiftUI

@MainActor
final class ShoreSettings: ObservableObject {
    static let shared = ShoreSettings()

    @Published var islandEnabled: Bool {
        didSet { defaults.set(islandEnabled, forKey: Keys.islandEnabled) }
    }

    @Published var dockEnabled: Bool {
        didSet { defaults.set(dockEnabled, forKey: Keys.dockEnabled) }
    }

    /// When MediaRemote has nothing to show, keep a quiet sample track so the island can be designed against.
    @Published var sampleWhenIdle: Bool {
        didSet { defaults.set(sampleWhenIdle, forKey: Keys.sampleWhenIdle) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let islandEnabled = "shore.islandEnabled"
        static let dockEnabled = "shore.dockEnabled"
        static let sampleWhenIdle = "shore.sampleWhenIdle"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        islandEnabled = defaults.object(forKey: Keys.islandEnabled) as? Bool ?? true
        dockEnabled = defaults.object(forKey: Keys.dockEnabled) as? Bool ?? true
        sampleWhenIdle = defaults.object(forKey: Keys.sampleWhenIdle) as? Bool ?? true
    }
}
