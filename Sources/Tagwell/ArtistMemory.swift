import Foundation
import Observation

/// Artists Tagwell remembers between launches. They become artist folders in the sidebar
/// and suggestions in the Artist field.
@Observable
final class ArtistMemory {
    static let defaultsKey = "rememberedArtists"

    private(set) var names: [String]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        names = defaults.stringArray(forKey: Self.defaultsKey) ?? []
    }

    func contains(_ name: String) -> Bool {
        names.contains(name)
    }

    func remember(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !names.contains(name) else { return }
        names.append(name)
        names.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        defaults.set(names, forKey: Self.defaultsKey)
    }

    func forget(_ name: String) {
        names.removeAll { $0 == name }
        defaults.set(names, forKey: Self.defaultsKey)
    }
}
