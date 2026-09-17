import Combine
import SwiftUI

@MainActor
final class ShoreSettings: ObservableObject {
    /// Main-actor singleton. Do not use as a default argument — those are nonisolated in Swift 6.
    static let shared = ShoreSettings()

    @Published var islandEnabled: Bool {
        didSet { defaults.set(islandEnabled, forKey: Keys.islandEnabled) }
    }

    /// When MediaRemote has nothing to show, keep a quiet sample track so the island can be designed against.
    @Published var sampleWhenIdle: Bool {
        didSet { defaults.set(sampleWhenIdle, forKey: Keys.sampleWhenIdle) }
    }

    /// Park dropped files on the island and drag them out later.
    @Published var fileShelfEnabled: Bool {
        didSet { defaults.set(fileShelfEnabled, forKey: Keys.fileShelfEnabled) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let islandEnabled = "shore.islandEnabled"
        static let sampleWhenIdle = "shore.sampleWhenIdle"
        static let fileShelfEnabled = "shore.fileShelfEnabled"
        static let dockEnabled = "shore.dockEnabled"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        islandEnabled = defaults.object(forKey: Keys.islandEnabled) as? Bool ?? true
        sampleWhenIdle = defaults.object(forKey: Keys.sampleWhenIdle) as? Bool ?? true
        // File parking lives on the island. Retired Dock Cove defaults no longer apply;
        // if someone only used Cove, turn the island shelf on so parked files still have a home.
        if defaults.object(forKey: Keys.fileShelfEnabled) == nil {
            let hadCove = defaults.object(forKey: Keys.dockEnabled) as? Bool ?? true
            fileShelfEnabled = hadCove
            defaults.set(fileShelfEnabled, forKey: Keys.fileShelfEnabled)
        } else {
            fileShelfEnabled = defaults.bool(forKey: Keys.fileShelfEnabled)
        }
        defaults.set(false, forKey: Keys.dockEnabled)
    }
}
