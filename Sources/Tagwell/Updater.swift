import Combine
import Sparkle
import SwiftUI

/// Looks for a newer Tagwell once a day and installs it, through Sparkle. The feed it reads and
/// the key that every update must be signed with are in Info.plist (SUFeedURL, SUPublicEDKey).
final class AppUpdater {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var updater: SPUUpdater { controller.updater }

    init() {
        // Started from `swift run` there is no app bundle and no Info.plist, so nothing to update.
        if Bundle.main.bundleURL.pathExtension == "app" {
            controller.startUpdater()
        }
    }
}

/// The "Check for Updates…" menu item. Greyed out while a check runs or when the updater is off.
struct CheckForUpdatesButton: View {
    let updater: SPUUpdater
    @State private var canCheck = false

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!canCheck)
            .onReceive(updater.publisher(for: \.canCheckForUpdates)) { canCheck = $0 }
    }
}
