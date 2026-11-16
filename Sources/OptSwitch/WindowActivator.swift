import AppKit
import ApplicationServices
import CoreGraphics

/// Brings the chosen `WindowItem` and its exact window instance to the front cleanly.
final class WindowActivator {
    static let shared = WindowActivator()

    private init() {}

    /// Activates the target application and raises the exact matching window via Accessibility API.
    func activate(window: WindowItem) {
        autoreleasepool {
            guard PermissionManager.shared.isAccessibilityGranted() else {
                // Fallback if Accessibility is somehow unavailable: just activate the app
                NSRunningApplication(processIdentifier: window.ownerPID)?.activate(options: [.activateIgnoringOtherApps])
                return
            }

            let appElement = AXUIElementCreateApplication(window.ownerPID)
            var windowsRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(
                appElement,
                kAXWindowsAttribute as CFString,
                &windowsRef
            )

            // 1. First raise and mark the specific AXWindow as main/focused before activating the app,
            //    so multi-window apps (like VS Code, Safari, Finder) don't flash the wrong window first.
            var matchedWindow: AXUIElement?
            if result == .success, let axWindows = windowsRef as? [AXUIElement], !axWindows.isEmpty {
                matchedWindow = findBestMatchingAXWindow(in: axWindows, matching: window) ?? axWindows.first
                if let target = matchedWindow {
                    AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
                    AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                    AXUIElementPerformAction(target, kAXRaiseAction as CFString)
                }
            }

            // 2. Activate the owning application
            if let runningApp = NSRunningApplication(processIdentifier: window.ownerPID) {
                runningApp.activate(options: [.activateIgnoringOtherApps])
            }

            // 3. Re-assert kAXRaiseAction after app activation to guarantee window order
            if let target = matchedWindow {
                AXUIElementPerformAction(target, kAXRaiseAction as CFString)
            }
        }
    }

    private func findBestMatchingAXWindow(in axWindows: [AXUIElement], matching item: WindowItem) -> AXUIElement? {
        var bestMatch: AXUIElement?
        var highestScore: Int = -1

        for axWin in axWindows {
            var score = 0

            // Check title match
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef) == .success,
               let axTitle = titleRef as? String,
               !axTitle.isEmpty {
                if axTitle == item.windowTitle {
                    score += 50
                } else if axTitle.localizedCaseInsensitiveContains(item.windowTitle) ||
                          item.windowTitle.localizedCaseInsensitiveContains(axTitle) {
                    score += 20
                }
            }

            // Check position & size match against CGWindow bounds
            if let axPos = copyCGPoint(from: axWin, attribute: kAXPositionAttribute as CFString),
               let axSize = copyCGSize(from: axWin, attribute: kAXSizeAttribute as CFString) {
                let dx = abs(axPos.x - item.bounds.origin.x)
                let dy = abs(axPos.y - item.bounds.origin.y)
                let dw = abs(axSize.width - item.bounds.size.width)
                let dh = abs(axSize.height - item.bounds.size.height)

                if dx < 4 && dy < 4 && dw < 4 && dh < 4 {
                    score += 100
                } else if dx < 25 && dy < 25 && dw < 25 && dh < 25 {
                    score += 40
                }
            }

            if score > highestScore {
                highestScore = score
                bestMatch = axWin
            }
        }

        return bestMatch
    }

    private func copyCGPoint(from element: AXUIElement, attribute: CFString) -> CGPoint? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &valueRef) == .success,
              let ref = valueRef,
              CFGetTypeID(ref) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = ref as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func copyCGSize(from element: AXUIElement, attribute: CFString) -> CGSize? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &valueRef) == .success,
              let ref = valueRef,
              CFGetTypeID(ref) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = ref as! AXValue
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }
        return size
    }
}
