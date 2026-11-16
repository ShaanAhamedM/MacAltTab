import AppKit

/// Main application controller coordinating the Menu Bar item, permissions, hotkeys, and switcher HUD.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var pauseMenuItem: NSMenuItem?

    private let switcherPanel = SwitcherPanel()
    private var isHUDVisible: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupMenuBar()
        setupSwitcherCallbacks()

        PermissionManager.shared.showOnboardingIfNeeded { [weak self] in
            self?.startEventTapIfPermitted()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyInterceptor.shared.stop()
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let symbol = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "MacAltTab") {
                symbol.isTemplate = true
                button.image = symbol
            } else {
                button.title = "MacAltTab"
            }
            button.toolTip = "MacAltTab - Offline Option+Tab Window Switcher"
        }

        let menu = NSMenu()
        menu.delegate = self

        let statusLine = NSMenuItem(title: "Status: Checking Permissions...", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        self.statusMenuItem = statusLine

        menu.addItem(NSMenuItem.separator())

        let pauseItem = NSMenuItem(title: "Pause Switcher", action: #selector(togglePauseSwitcher), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)
        self.pauseMenuItem = pauseItem

        let permItem = NSMenuItem(title: "Permissions & Setup...", action: #selector(openPermissionsWindow), keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)

        menu.addItem(NSMenuItem.separator())

        let emergencyQuitItem = NSMenuItem(
            title: "Emergency Quit (Ctrl+Opt+Esc)",
            action: #selector(emergencyQuit),
            keyEquivalent: "q"
        )
        emergencyQuitItem.target = self
        menu.addItem(emergencyQuitItem)

        item.menu = menu
        self.statusItem = item

        updateMenuStatusText()
    }

    func menuWillOpen(_ menu: NSMenu) {
        if PermissionManager.shared.isAccessibilityGranted() {
            _ = HotKeyInterceptor.shared.start()
        }
        updateMenuStatusText()
    }

    private func updateMenuStatusText() {
        if HotKeyInterceptor.shared.isPaused {
            statusMenuItem?.title = "Paused - Option+Tab Disabled"
            pauseMenuItem?.state = .on
        } else if PermissionManager.shared.isAccessibilityGranted() {
            statusMenuItem?.title = "Active - Option+Tab Ready"
            pauseMenuItem?.state = .off
        } else {
            statusMenuItem?.title = "Waiting for Accessibility Permission"
            pauseMenuItem?.state = .off
        }
    }

    // MARK: - HotKey & Switcher Coordination

    private func startEventTapIfPermitted() {
        let started = HotKeyInterceptor.shared.start()
        if !started {
            statusMenuItem?.title = "Permission Required (Click Permissions & Setup)"
        } else {
            updateMenuStatusText()
        }
    }

    private func setupSwitcherCallbacks() {
        let interceptor = HotKeyInterceptor.shared

        interceptor.onCycleForward = { [weak self] in
            self?.handleCycle(forward: true)
        }

        interceptor.onCycleBackward = { [weak self] in
            self?.handleCycle(forward: false)
        }

        interceptor.onCommitSelection = { [weak self] in
            self?.commitAndCloseSwitcher()
        }

        interceptor.onCancelSelection = { [weak self] in
            self?.cancelAndCloseSwitcher()
        }

        switcherPanel.onMouseSelectWindow = { [weak self] chosenWindow in
            guard let self = self else { return }
            self.isHUDVisible = false
            HotKeyInterceptor.shared.setSwitcherActive(false)
            self.switcherPanel.hideHUD()
            WindowActivator.shared.activate(window: chosenWindow)
        }
    }

    private func handleCycle(forward: Bool) {
        if !isHUDVisible {
            // Fetch windows and thumbnails ONCE when the user first presses Option+Tab
            let windows = WindowEngine.shared.fetchSwitchableWindows(includeThumbnails: true)
            guard !windows.isEmpty else {
                HotKeyInterceptor.shared.setSwitcherActive(false)
                return
            }

            let initialSelection: Int
            if windows.count > 1 {
                initialSelection = forward ? 1 : (windows.count - 1)
            } else {
                initialSelection = 0
            }

            // Fast-Tap Guard: If the user already released the Option key before the initial window fetch completed,
            // immediately activate the target window without leaving the HUD stuck on screen!
            if !HotKeyInterceptor.isOptionKeyHeldDown() {
                HotKeyInterceptor.shared.setSwitcherActive(false)
                self.isHUDVisible = false
                WindowActivator.shared.activate(window: windows[initialSelection])
                return
            }

            isHUDVisible = true
            switcherPanel.present(with: windows, initialIndex: initialSelection)
        } else {
            // On repeat presses of Tab while Option is held, only move the highlight index
            let delta = forward ? 1 : -1
            switcherPanel.updateSelection(to: switcherPanel.selectedIndex + delta)
        }
    }

    private func commitAndCloseSwitcher() {
        guard isHUDVisible else { return }
        let selected = switcherPanel.currentlySelectedWindow()
        isHUDVisible = false
        switcherPanel.hideHUD()

        if let targetWindow = selected {
            WindowActivator.shared.activate(window: targetWindow)
        }
    }

    private func cancelAndCloseSwitcher() {
        guard isHUDVisible else { return }
        isHUDVisible = false
        switcherPanel.hideHUD()
    }

    // MARK: - Menu Actions

    @objc private func togglePauseSwitcher() {
        let interceptor = HotKeyInterceptor.shared
        interceptor.isPaused.toggle()
        if interceptor.isPaused && isHUDVisible {
            HotKeyInterceptor.shared.setSwitcherActive(false)
            cancelAndCloseSwitcher()
        }
        updateMenuStatusText()
    }

    @objc private func openPermissionsWindow() {
        PermissionManager.shared.showOnboardingIfNeeded { [weak self] in
            self?.startEventTapIfPermitted()
        }
        PermissionManager.shared.showOnboardingWindow()
    }

    @objc private func emergencyQuit() {
        HotKeyInterceptor.shared.stop()
        NSApplication.shared.terminate(nil)
    }
}
