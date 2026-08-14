import Foundation

final class PreferencesStore {
    static let shared = PreferencesStore()
    private let key = "squadcomms.preferences.v1"

    private(set) var current: Preferences {
        didSet { persist() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Preferences.self, from: data) {
            current = decoded
        } else {
            current = Preferences()
        }
    }

    func update(_ mutate: (inout Preferences) -> Void) {
        var copy = current
        mutate(&copy)
        current = copy
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: key)
            NSUbiquitousKeyValueStore.default.set(data, forKey: key)
        }
    }
}
