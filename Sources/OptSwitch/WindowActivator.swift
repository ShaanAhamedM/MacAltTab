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
            // 1. Activate the owning application
            if let runningApp = NSRunningApplication(processIdentifier: window.ownerPID) {
                runningApp.activate(options: [.activateIgnoringOtherApps])
            }

            // 2. Use Accessibility API to find and raise the specific window (by bounds and title)
            guard PermissionManager.shared.isAccessibilityGranted() else {
                return
            }

            let appElement = AXUIElementCreateApplication(window.ownerPID)
            var windowsRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(
                appElement,
                kAXWindowsAttribute as CFString,
                &windowsRef
            )

            guard result == .success, let axWindows = windowsRef as? [AXUIElement], !axWindows.isEmpty else {
                return
            }

            let targetElement = findBestMatchingAXWindow(in: axWindows, matching: window) ?? axWindows.first
            if let target = targetElement {
                AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue)
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
