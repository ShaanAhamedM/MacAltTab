import AppKit
import CoreGraphics
import Foundation

/// Ultra-fast, non-blocking `CGEventTap` keyboard listener for `Option + Tab` and `Ctrl + Opt + Esc`.
/// Executes in microseconds inside the callback and dispatches all UI work asynchronously to the main queue.
final class HotKeyInterceptor {
    static let shared = HotKeyInterceptor()

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Tracked state flags for the event tap callback.
    fileprivate var isSwitcherActive: Bool = false
    var isPaused: Bool = false

    // Main-thread UI callbacks
    var onCycleForward: (() -> Void)?
    var onCycleBackward: (() -> Void)?
    var onNavigateDirection: ((Int) -> Void)?
    var onCommitSelection: (() -> Void)?
    var onCancelSelection: (() -> Void)?

    private init() {}

    /// Starts the global CGEventTap at `.cgSessionEventTap`, `.headInsertEventTap`, `.defaultTap`.
    @discardableResult
    func start() -> Bool {
        if let existingTap = eventTap {
            if CFMachPortIsValid(existingTap) {
                CGEvent.tapEnable(tap: existingTap, enable: true)
                return true
            }
            stop()
        }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotKeyEventTapCallback,
            userInfo: selfPtr
        ) else {
            return false
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// Cleanly disables and removes the event tap.
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        isSwitcherActive = false
    }

    /// Updates whether the HUD is currently visible so the tap knows when to intercept Escape or Option release.
    func setSwitcherActive(_ active: Bool) {
        isSwitcherActive = active
    }

    /// Checks whether the Option (`.maskAlternate`) key is currently physically held down.
    static func isOptionKeyHeldDown() -> Bool {
        let currentFlags = CGEventSource.flagsState(.combinedSessionState)
        return currentFlags.contains(.maskAlternate)
    }
}

/// Top-level C function pointer for CGEventTapCallBack.
/// RULE #1: Must finish in < 1 millisecond. Zero window queries, zero screenshots, zero synchronous UI updates.
private func hotKeyEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let interceptor = Unmanaged<HotKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()

    // 1. Watchdog Recovery: Immediately re-enable tap if macOS disabled it due to timeout or user input
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = interceptor.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    let flags = event.flags

    // 2. EMERGENCY KILLSWITCH: Control + Option + Escape (keyCode 53)
    if type == .keyDown {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == 53 && flags.contains(.maskControl) && flags.contains(.maskAlternate) {
            if let tap = interceptor.eventTap {
                CGEvent.tapEnable(tap: tap, enable: false)
            }
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
            return nil
        }
    }

    // If paused by user from the Menu Bar, pass all normal events through untouched
    if interceptor.isPaused {
        return Unmanaged.passUnretained(event)
    }

    // 3. Handle KeyDown events (Option + Tab, Option + Shift + Tab, Arrow keys & Escape while active)
    if type == .keyDown {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Option + Tab (keyCode 48 = Tab, with Option held and Command/Control NOT held)
        if keyCode == 48 && flags.contains(.maskAlternate) && !flags.contains(.maskCommand) && !flags.contains(.maskControl) {
            let isShiftHeld = flags.contains(.maskShift)
            interceptor.isSwitcherActive = true

            DispatchQueue.main.async {
                if isShiftHeld {
                    interceptor.onCycleBackward?()
                } else {
                    interceptor.onCycleForward?()
                }
            }
            // Swallow the Tab key event so it never types a tab into the active application
            return nil
        }

        // Additional convenience keys while switcher HUD is open
        if interceptor.isSwitcherActive {
            switch keyCode {
            case 53: // Escape -> cancel and close HUD
                interceptor.isSwitcherActive = false
                DispatchQueue.main.async {
                    interceptor.onCancelSelection?()
                }
                return nil
            case 36, 76: // Return or Numpad Enter -> commit selection immediately
                interceptor.isSwitcherActive = false
                DispatchQueue.main.async {
                    interceptor.onCommitSelection?()
                }
                return nil
            case 123: // Left Arrow -> previous item
                DispatchQueue.main.async {
                    interceptor.onCycleBackward?()
                }
                return nil
            case 124: // Right Arrow -> next item
                DispatchQueue.main.async {
                    interceptor.onCycleForward?()
                }
                return nil
            default:
                break
            }
        }
    }

    // 4. Handle Option key release (.flagsChanged) while switcher is open -> commit selection
    if type == .flagsChanged && interceptor.isSwitcherActive {
        if !flags.contains(.maskAlternate) {
            interceptor.isSwitcherActive = false
            DispatchQueue.main.async {
                interceptor.onCommitSelection?()
            }
        }
    }

    return Unmanaged.passUnretained(event)
}
