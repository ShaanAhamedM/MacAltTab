import AppKit
import ApplicationServices
import CoreGraphics

/// Safely checks and guides the user through macOS Accessibility & Screen Recording permissions
/// without spamming system popups.
final class PermissionManager: NSObject {
    static let shared = PermissionManager()

    private var onboardingWindow: NSWindow?
    private var axStatusDot: NSView?
    private var axStatusLabel: NSTextField?
    private var screenStatusDot: NSView?
    private var screenStatusLabel: NSTextField?
    private var refreshTimer: Timer?
    private var onAccessibilityGranted: (() -> Void)?

    private override init() {
        super.init()
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
    }

    /// Shows the onboarding window ONLY if Accessibility permission is not yet granted.
    func showOnboardingIfNeeded(onGranted: @escaping () -> Void) {
        self.onAccessibilityGranted = onGranted
        if isAccessibilityGranted() {
            onGranted()
            return
        }
        showOnboardingWindow()
    }

    func showOnboardingWindow() {
        if let existing = onboardingWindow {
            updateStatusUI()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "OptSwitch Permissions Setup"
        window.isReleasedWhenClosed = false
        window.center()

        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.wantsLayer = true

        // Title
        let titleLabel = NSTextField(labelWithString: "OptSwitch Setup (100% Offline)")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 18)
        titleLabel.frame = NSRect(x: 24, y: 245, width: 412, height: 28)
        contentView.addSubview(titleLabel)

        let subtitleLabel = NSTextField(wrappingLabelWithString: "OptSwitch runs locally with zero internet access. Accessibility permission is required to listen for Option+Tab and switch windows.")
        subtitleLabel.font = NSFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.frame = NSRect(x: 24, y: 195, width: 412, height: 42)
        contentView.addSubview(subtitleLabel)

        // Accessibility row
        let axDot = NSView(frame: NSRect(x: 24, y: 152, width: 12, height: 12))
        axDot.wantsLayer = true
        axDot.layer?.cornerRadius = 6
        contentView.addSubview(axDot)
        self.axStatusDot = axDot

        let axLabel = NSTextField(labelWithString: "Accessibility: Checking...")
        axLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        axLabel.frame = NSRect(x: 46, y: 148, width: 220, height: 20)
        contentView.addSubview(axLabel)
        self.axStatusLabel = axLabel

        let axButton = NSButton(title: "Open System Settings", target: self, action: #selector(handleOpenAccessibilitySettings))
        axButton.bezelStyle = .rounded
        axButton.frame = NSRect(x: 276, y: 142, width: 160, height: 32)
        contentView.addSubview(axButton)

        // Screen Recording row (Optional for thumbnails & window titles)
        let screenDot = NSView(frame: NSRect(x: 24, y: 102, width: 12, height: 12))
        screenDot.wantsLayer = true
        screenDot.layer?.cornerRadius = 6
        contentView.addSubview(screenDot)
        self.screenStatusDot = screenDot

        let screenLabel = NSTextField(labelWithString: "Screen Recording (Optional): Checking...")
        screenLabel.font = NSFont.systemFont(ofSize: 13)
        screenLabel.frame = NSRect(x: 46, y: 98, width: 220, height: 20)
        contentView.addSubview(screenLabel)
        self.screenStatusLabel = screenLabel

        let screenButton = NSButton(title: "Grant Preview Access", target: self, action: #selector(handleOpenScreenSettings))
        screenButton.bezelStyle = .rounded
        screenButton.frame = NSRect(x: 276, y: 92, width: 160, height: 32)
        contentView.addSubview(screenButton)

        // Footer note
        let footerLabel = NSTextField(labelWithString: "Emergency Panic Exit at any time: Control + Option + Escape")
        footerLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        footerLabel.textColor = .tertiaryLabelColor
        footerLabel.frame = NSRect(x: 24, y: 24, width: 412, height: 20)
        contentView.addSubview(footerLabel)

        window.contentView = contentView
        self.onboardingWindow = window

        updateStatusUI()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        startMonitoringPermissions()
    }

    @objc private func handleOpenAccessibilitySettings() {
        requestAccessibilityPermission()
    }

    @objc private func handleOpenScreenSettings() {
        requestScreenRecordingPermission()
    }

    private func startMonitoringPermissions() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateStatusUI()
            if self.isAccessibilityGranted() {
                self.refreshTimer?.invalidate()
                self.refreshTimer = nil
                self.onboardingWindow?.close()
                self.onAccessibilityGranted?()
                self.onAccessibilityGranted = nil
            }
        }
    }

    private func updateStatusUI() {
        let axGranted = isAccessibilityGranted()
        axStatusDot?.layer?.backgroundColor = (axGranted ? NSColor.systemGreen : NSColor.systemRed).cgColor
        axStatusLabel?.stringValue = axGranted ? "Accessibility: Granted" : "Accessibility: Not Granted"

        let screenGranted = isScreenRecordingGranted()
        screenStatusDot?.layer?.backgroundColor = (screenGranted ? NSColor.systemGreen : NSColor.systemOrange).cgColor
        screenStatusLabel?.stringValue = screenGranted ? "Screen Previews: Granted" : "Screen Previews: App Icons Only"
    }
}
