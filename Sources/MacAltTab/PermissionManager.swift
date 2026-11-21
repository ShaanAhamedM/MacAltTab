import AppKit
import ApplicationServices
import CoreGraphics

/// Safely checks and guides the user through macOS Accessibility & Screen Recording permissions
/// without spamming system popups or TCC IPC calls.
final class PermissionManager: NSObject, NSWindowDelegate {
    static let shared = PermissionManager()

    private var onboardingWindow: NSWindow?
    private var axStatusDot: NSView?
    private var axStatusLabel: NSTextField?
    private var screenStatusDot: NSView?
    private var screenStatusLabel: NSTextField?
    private var restartButton: NSButton?
    private var refreshTimer: Timer?

    private var onAccessibilityGranted: (() -> Void)?
    private var shouldAutoCloseOnGrant: Bool = false
    private var distributedObserver: NSObjectProtocol?

    private override init() {
        super.init()
        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // macOS sends this notification slightly before TCC state settles; check after a tiny delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self?.handlePermissionCheckTick()
            }
        }
    }

    deinit {
        if let observer = distributedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    /// Checks whether Accessibility permission is granted WITHOUT triggering a system prompt.
    func isAccessibilityGranted() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Prompts macOS Accessibility permission dialog ONLY when explicitly clicked by the user.
    func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Checks whether Screen Recording permission is granted WITHOUT triggering a system prompt.
    func isScreenRecordingGranted() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    /// Requests Screen Recording permission ONLY when explicitly clicked by the user.
    func requestScreenRecordingPermission() {
        _ = CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        restartButton?.isHidden = false
    }

    /// Shows the onboarding window ONLY if Accessibility permission is not yet granted.
    func showOnboardingIfNeeded(onGranted: @escaping () -> Void) {
        self.onAccessibilityGranted = onGranted
        if isAccessibilityGranted() {
            onGranted()
            return
        }
        showOnboardingWindow(autoCloseWhenGranted: true, onGranted: onGranted)
    }

    func showOnboardingWindow(autoCloseWhenGranted: Bool = false, onGranted: (() -> Void)? = nil) {
        if let onGranted = onGranted {
            self.onAccessibilityGranted = onGranted
        }
        self.shouldAutoCloseOnGrant = autoCloseWhenGranted

        if let existing = onboardingWindow {
            updateStatusUI(checkScreenRecording: true)
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            startMonitoringPermissions()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacAltTab Permissions Setup"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.wantsLayer = true

        // Title
        let titleLabel = NSTextField(labelWithString: "MacAltTab Setup (100% Offline)")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 18)
        titleLabel.frame = NSRect(x: 24, y: 266, width: 432, height: 28)
        contentView.addSubview(titleLabel)

        let subtitleLabel = NSTextField(wrappingLabelWithString: "MacAltTab runs locally with zero internet access. Accessibility permission is required to listen for Option+Tab and switch windows.")
        subtitleLabel.font = NSFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.frame = NSRect(x: 24, y: 214, width: 432, height: 42)
        contentView.addSubview(subtitleLabel)

        // Accessibility row
        let axDot = NSView(frame: NSRect(x: 24, y: 170, width: 12, height: 12))
        axDot.wantsLayer = true
        axDot.layer?.cornerRadius = 6
        contentView.addSubview(axDot)
        self.axStatusDot = axDot

        let axLabel = NSTextField(labelWithString: "Accessibility: Checking...")
        axLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        axLabel.frame = NSRect(x: 46, y: 166, width: 230, height: 20)
        contentView.addSubview(axLabel)
        self.axStatusLabel = axLabel

        let axButton = NSButton(title: "Open System Settings", target: self, action: #selector(handleOpenAccessibilitySettings))
        axButton.bezelStyle = .rounded
        axButton.frame = NSRect(x: 286, y: 160, width: 170, height: 32)
        contentView.addSubview(axButton)

        // Screen Recording row (Optional for thumbnails & window titles)
        let screenDot = NSView(frame: NSRect(x: 24, y: 118, width: 12, height: 12))
        screenDot.wantsLayer = true
        screenDot.layer?.cornerRadius = 6
        contentView.addSubview(screenDot)
        self.screenStatusDot = screenDot

        let screenLabel = NSTextField(labelWithString: "Screen Previews: Checking...")
        screenLabel.font = NSFont.systemFont(ofSize: 13)
        screenLabel.frame = NSRect(x: 46, y: 114, width: 230, height: 20)
        contentView.addSubview(screenLabel)
        self.screenStatusLabel = screenLabel

        let screenButton = NSButton(title: "Grant Preview Access", target: self, action: #selector(handleOpenScreenSettings))
        screenButton.bezelStyle = .rounded
        screenButton.frame = NSRect(x: 286, y: 108, width: 170, height: 32)
        contentView.addSubview(screenButton)

        // Helpful hint + Relaunch button (for Screen Recording changes or stuck TCC states)
        let hintLabel = NSTextField(wrappingLabelWithString: "Tip: If you just enabled Screen Recording, restart MacAltTab for live window previews to appear.")
        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.frame = NSRect(x: 24, y: 56, width: 280, height: 34)
        contentView.addSubview(hintLabel)

        let relaunchBtn = NSButton(title: "Restart MacAltTab", target: self, action: #selector(handleRestartApp))
        relaunchBtn.bezelStyle = .rounded
        relaunchBtn.frame = NSRect(x: 316, y: 58, width: 140, height: 30)
        contentView.addSubview(relaunchBtn)
        self.restartButton = relaunchBtn

        // Footer note
        let footerLabel = NSTextField(labelWithString: "Emergency Panic Exit at any time: Control + Option + Escape")
        footerLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        footerLabel.textColor = .tertiaryLabelColor
        footerLabel.frame = NSRect(x: 24, y: 20, width: 432, height: 20)
        contentView.addSubview(footerLabel)

        window.contentView = contentView
        self.onboardingWindow = window

        updateStatusUI(checkScreenRecording: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        startMonitoringPermissions()
    }

    func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    @objc private func handleOpenAccessibilitySettings() {
        requestAccessibilityPermission()
    }

    @objc private func handleOpenScreenSettings() {
        requestScreenRecordingPermission()
    }

    @objc private func handleRestartApp() {
        let bundleURL = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundleURL.path]
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApplication.shared.terminate(nil)
        }
    }

    private func startMonitoringPermissions() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.handlePermissionCheckTick()
        }
    }

    private func handlePermissionCheckTick() {
        let axGranted = isAccessibilityGranted()
        updateStatusUI(checkScreenRecording: false)

        if axGranted {
            onAccessibilityGranted?()
            if shouldAutoCloseOnGrant {
                refreshTimer?.invalidate()
                refreshTimer = nil
                shouldAutoCloseOnGrant = false
                onboardingWindow?.close()
            }
        }
    }

    private func updateStatusUI(checkScreenRecording: Bool) {
        let axGranted = isAccessibilityGranted()
        axStatusDot?.layer?.backgroundColor = (axGranted ? NSColor.systemGreen : NSColor.systemRed).cgColor
        axStatusLabel?.stringValue = axGranted ? "Accessibility: Granted" : "Accessibility: Not Granted"

        if checkScreenRecording {
            let screenGranted = isScreenRecordingGranted()
            screenStatusDot?.layer?.backgroundColor = (screenGranted ? NSColor.systemGreen : NSColor.systemOrange).cgColor
            screenStatusLabel?.stringValue = screenGranted ? "Screen Previews: Granted" : "Screen Previews: App Icons Only"
        }
    }
}
