import AppKit
import Sparkle

/// Sparkle owns downloading, signature verification, installation, and relaunch.
/// Builds without a public signing key keep working with updates disabled.
@MainActor
final class AppUpdater: NSObject {
    private var controller: SPUStandardUpdaterController?
    private var startupError: String?

    func start() {
        guard controller == nil, Self.unavailableReason(bundleURL: Bundle.main.bundleURL,
                                                       info: Bundle.main.infoDictionary ?? [:]) == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        do {
            try controller.updater.start()
            self.controller = controller
        } catch {
            startupError = error.localizedDescription
        }
    }

    func menuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Check for updates…", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        item.target = self
        item.isEnabled = controller?.updater.canCheckForUpdates ?? false
        item.toolTip = startupError ?? Self.unavailableReason(bundleURL: Bundle.main.bundleURL,
                                                             info: Bundle.main.infoDictionary ?? [:])
        return item
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(sender)
    }

    nonisolated static func unavailableReason(bundleURL: URL, info: [String: Any]) -> String? {
        let path = bundleURL.resolvingSymlinksInPath().path
        guard bundleURL.pathExtension == "app" else {
            return "Updates are available in the installed app bundle."
        }
        if path.contains("/AppTranslocation/") {
            return "Move pullbar to Applications before updating."
        }
        if path.contains("/Cellar/") || path.contains("/Caskroom/") {
            return "Update this installation with Homebrew."
        }
        guard let key = info["SUPublicEDKey"] as? String,
              let data = Data(base64Encoded: key), data.count == 32 else {
            return "Update signing is not configured for this build."
        }
        guard let value = info["SUFeedURL"] as? String,
              let feed = URL(string: value), feed.scheme == "https", feed.host != nil else {
            return "A secure update feed is not configured for this build."
        }
        return nil
    }
}
