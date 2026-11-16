import AppKit
import Darwin

// 1. Run mandatory offline & anti-injection security audit immediately on launch
SecurityAudit.performStartupAudit()

// 2. Support automated self-test verification (--self-test)
if CommandLine.arguments.contains("--self-test") {
    let auditPassed = SecurityAudit.performStartupAudit()
    let memoryPassed = WindowEngine.shared.runMemoryStressCheck(iterations: 100)
    let memMB = String(format: "%.2f", WindowEngine.currentResidentMemoryMB())
    print("[OptSwitch Self-Test] SecurityAudit=\(auditPassed), Memory100xCheck=\(memoryPassed), ResidentRAM=\(memMB)MB")
    Darwin.exit((auditPassed && memoryPassed) ? EXIT_SUCCESS : EXIT_FAILURE)
}

// 3. Start native AppKit menu bar application loop
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
