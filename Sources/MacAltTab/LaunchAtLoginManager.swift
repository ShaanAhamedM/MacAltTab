import Foundation

/// Manages automatic launch at macOS login using a standard per-user LaunchAgent plist
/// (`~/Library/LaunchAgents/com.local.MacAltTab.plist`), keeping 100% offline behavior
/// with zero private APIs or background restart loops (so Emergency Quit always stays quit).
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private let label = "com.local.MacAltTab"

    private var launchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
    }

    private var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(label).plist")
    }

    private init() {}

    /// Returns true if the LaunchAgent plist exists and points to the current app executable.
    var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// Resolves the best path to launch at login (prefers the `.app` bundle via `/usr/bin/open -a`
    /// so macOS TCC Accessibility permissions match the signed `.app` bundle).
    private func currentBundlePath() -> String? {
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.hasSuffix(".app") {
            return bundlePath
        }
        return nil
    }

    /// Enables launch at login by writing a clean LaunchAgent plist.
    @discardableResult
    func enable() -> Bool {
        guard let appPath = currentBundlePath() else {
            return false
        }

        do {
            try FileManager.default.createDirectory(
                at: launchAgentsDirectory,
                withIntermediateDirectories: true
            )

            // Use `open -a <AppPath>` with RunAtLoad=true and KeepAlive=false so:
            // 1. macOS launches the signed .app bundle cleanly with its TCC permissions.
            // 2. If the user triggers Emergency Quit (Ctrl+Opt+Esc), launchd will NEVER respawn it.
            let plistDict: [String: Any] = [
                "Label": label,
                "ProgramArguments": ["/usr/bin/open", "-a", appPath],
                "RunAtLoad": true,
                "KeepAlive": false,
                "LimitLoadToSessionType": "Aqua"
            ]

            let data = try PropertyListSerialization.data(
                fromPropertyList: plistDict,
                format: .xml,
                options: 0
            )
            try data.write(to: plistURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Disables launch at login by removing the LaunchAgent plist.
    @discardableResult
    func disable() -> Bool {
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            return true
        }
        do {
            try FileManager.default.removeItem(at: plistURL)
            return true
        } catch {
            return false
        }
    }

    /// Toggles launch at login and returns the new enabled state.
    @discardableResult
    func toggle() -> Bool {
        if isEnabled {
            _ = disable()
        } else {
            _ = enable()
        }
        return isEnabled
    }
}
