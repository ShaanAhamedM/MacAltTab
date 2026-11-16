import AppKit
import Darwin

// 1. Run mandatory offline & anti-injection security audit immediately on launch
SecurityAudit.performStartupAudit()

// 2. Support automated self-test verification (--self-test)
if CommandLine.arguments.contains("--self-test") {
    let auditPassed = SecurityAudit.performStartupAudit()
    let memoryPassed = WindowEngine.shared.runMemoryStressCheck(iterations: 100)
    let windows = WindowEngine.shared.fetchSwitchableWindows(includeThumbnails: false)

    // Test UI panel state cycling & wrap-around logic in headless mode
    let panel = SwitcherPanel()
    if !windows.isEmpty {
        panel.present(with: windows, initialIndex: 0)
        panel.updateSelection(to: 1)
        panel.updateSelection(to: -1)
        panel.hideHUD()
    }

    let memMB = String(format: "%.2f", WindowEngine.currentResidentMemoryMB())
    print("[MacAltTab Self-Test] SecurityAudit=\(auditPassed), Memory100xCheck=\(memoryPassed), DiscoveredWindows=\(windows.count), ResidentRAM=\(memMB)MB")
    for (idx, win) in windows.prefix(5).enumerated() {
        print("  [\(idx)] \(win.appName) — \"\(win.windowTitle)\" (\(Int(win.bounds.width))x\(Int(win.bounds.height)))")
    }
    Darwin.exit((auditPassed && memoryPassed) ? EXIT_SUCCESS : EXIT_FAILURE)
}

// 3. Start native AppKit menu bar application loop
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
