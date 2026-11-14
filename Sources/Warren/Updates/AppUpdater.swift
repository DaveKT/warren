import Combine
import Sparkle
import SwiftUI

/// Automatic updates through Sparkle. The feed address (`SUFeedURL`) and
/// the public key that update archives must be signed with
/// (`SUPublicEDKey`) come from the app's Info.plist, which build-app.sh
/// writes.
///
/// Sparkle only starts in a real app bundle that has both keys, so
/// development runs (`swift build && .build/debug/Warren`) don't show an
/// "Unable to check for updates" alert at launch.
@MainActor
final class AppUpdater: ObservableObject {
    private let controller: SPUStandardUpdaterController?
    private var cancellable: AnyCancellable?

    /// False while a check is already in progress.
    @Published private(set) var canCheckForUpdates = false

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        guard Bundle.main.bundleURL.pathExtension == "app",
              info["SUFeedURL"] != nil,
              info["SUPublicEDKey"] != nil
        else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
    }

    /// Whether updating is available at all (false in development runs).
    var isEnabled: Bool { controller != nil }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// Check for updates once a day in the background.
    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    /// Download updates in the background and install them when Warren quits.
    var automaticallyDownloadsUpdates: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyDownloadsUpdates = newValue
        }
    }
}

/// Warren → Check for Updates…
struct CheckForUpdatesButton: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        if updater.isEnabled {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
    }
}
