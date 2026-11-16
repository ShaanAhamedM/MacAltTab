import AppKit

@main
struct OptSwitchMain {
    static func main() {
        SecurityAudit.performStartupAudit()

        if CommandLine.arguments.contains("--self-test") {
            let passed = WindowEngine.shared.runMemoryStressCheck(iterations: 100)
            let memMB = String(format: "%.2f", WindowEngine.currentResidentMemoryMB())
            print("[Self-Test] 100x WindowEngine memory check passed: \(passed) (Resident RAM: \(memMB) MB)")
            Darwin.exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
        }
    }
}
