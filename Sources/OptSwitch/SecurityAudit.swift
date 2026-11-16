import Foundation
import Darwin

/// Verifies at startup that no dynamic library injection or network proxy hijacking is active.
enum SecurityAudit {
    /// Runs startup security checks and exits immediately if code injection is detected.
    @discardableResult
    static func performStartupAudit() -> Bool {
        let env = ProcessInfo.processInfo.environment

        // 1. Refuse to launch if DYLD injection variables are present
        let forbiddenDyldVars = [
            "DYLD_INSERT_LIBRARIES",
            "DYLD_FORCE_FLAT_NAMESPACE",
            "DYLD_LIBRARY_PATH",
            "DYLD_FRAMEWORK_PATH"
        ]

        for key in forbiddenDyldVars {
            if let value = env[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fputs("[OptSwitch Security Alert] Detected unsafe environment variable \(key). Refusing to launch.\n", stderr)
                Darwin.exit(EXIT_FAILURE)
            }
        }

        // 2. Strip any network proxy variables from our process environment as extra defense-in-depth
        let proxyVars = [
            "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY",
            "http_proxy", "https_proxy", "all_proxy"
        ]
        for proxyKey in proxyVars {
            if env[proxyKey] != nil {
                unsetenv(proxyKey)
            }
        }

        return true
    }
}
