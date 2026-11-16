import AppKit
import CoreGraphics
import Foundation
import Darwin

/// Represents a single switchable on-screen application window.
struct WindowItem {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let appName: String
    let windowTitle: String
    let bounds: CGRect
    let appIcon: NSImage?
    let thumbnail: NSImage?
}

/// Memory-safe window discovery engine wrapped strictly inside `autoreleasepool`.
final class WindowEngine {
    static let shared = WindowEngine()

    /// Maximum thumbnail dimensions (320x200) to guarantee low GPU/RAM footprint (<35MB).
    private let maxThumbnailSize = NSSize(width: 320, height: 200)

    private init() {}

    /// Fetches all currently switchable on-screen application windows once when the HUD opens.
    /// Strictly wrapped in `autoreleasepool` to prevent CoreGraphics memory leaks.
    func fetchSwitchableWindows(includeThumbnails: Bool = true) -> [WindowItem] {
        return autoreleasepool {
            let myPID = ProcessInfo.processInfo.processIdentifier
            let canCaptureScreen = includeThumbnails && PermissionManager.shared.isScreenRecordingGranted()

            let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
            guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
                return []
            }

            var results: [WindowItem] = []
            results.reserveCapacity(min(infoList.count, 24))

            for entry in infoList {
                // 1. Only normal application windows (kCGWindowLayer == 0)
                guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else {
                    continue
                }

                // 2. Valid owner PID, excluding our own switcher process
                guard let pidInt = entry[kCGWindowOwnerPID as String] as? Int32, pidInt > 0, pidInt != myPID else {
                    continue
                }
                let pid = pid_t(pidInt)

                // 3. Valid window ID
                guard let rawWindowID = entry[kCGWindowNumber as String] as? UInt32, rawWindowID > 0 else {
                    continue
                }
                let windowID = CGWindowID(rawWindowID)

                // 4. Filter out transparent or hidden overlay windows
                if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha <= 0.01 {
                    continue
                }

                // 5. Filter out tiny utility windows smaller than 50x50
                guard let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                      let bounds = CGRect(dictionaryRepresentation: boundsDict),
                      bounds.width > 50,
                      bounds.height > 50 else {
                    continue
                }

                // 6. Resolve running application & icon
                let runningApp = NSRunningApplication(processIdentifier: pid)
                let ownerName = (entry[kCGWindowOwnerName as String] as? String)
                    ?? runningApp?.localizedName
                    ?? "Application"
                let rawTitle = (entry[kCGWindowName as String] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let displayTitle = rawTitle.isEmpty ? ownerName : rawTitle
                let icon = runningApp?.icon

                // 7. Capture capped thumbnail (max 320x200) inside its own inner autoreleasepool if permitted
                let thumbnail: NSImage? = canCaptureScreen ? captureCappedThumbnail(for: windowID) : nil

                let item = WindowItem(
                    windowID: windowID,
                    ownerPID: pid,
                    appName: ownerName,
                    windowTitle: displayTitle,
                    bounds: bounds,
                    appIcon: icon,
                    thumbnail: thumbnail
                )
                results.append(item)

                // Cap maximum tracked windows to 24 to keep UI fast and memory bounded
                if results.count >= 24 {
                    break
                }
            }

            return results
        }
    }

    /// Captures and downscales a window image to at most 320x200 inside an autoreleasepool.
    private func captureCappedThumbnail(for windowID: CGWindowID) -> NSImage? {
        return autoreleasepool {
            let imageOptions: CGWindowImageOption = [.boundsIgnoreFraming, .nominalResolution]
            guard let cgImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowID,
                imageOptions
            ) else {
                return nil
            }

            let srcWidth = CGFloat(cgImage.width)
            let srcHeight = CGFloat(cgImage.height)
            guard srcWidth > 1, srcHeight > 1 else {
                return nil
            }

            let widthRatio = maxThumbnailSize.width / srcWidth
            let heightRatio = maxThumbnailSize.height / srcHeight
            let scale = min(1.0, min(widthRatio, heightRatio))

            let targetWidth = max(1, Int( (srcWidth * scale).rounded() ))
            let targetHeight = max(1, Int( (srcHeight * scale).rounded() ))

            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: nil,
                      width: targetWidth,
                      height: targetHeight,
                      bitsPerComponent: 8,
                      bytesPerRow: 0,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return nil
            }

            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

            guard let scaledCGImage = context.makeImage() else {
                return nil
            }

            return NSImage(cgImage: scaledCGImage, size: NSSize(width: targetWidth, height: targetHeight))
        }
    }

    /// Returns current process resident memory in megabytes (MB).
    static func currentResidentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0.0 }
        return Double(info.resident_size) / (1024.0 * 1024.0)
    }

    /// Runs a 100-iteration dry-run check to verify memory stays flat and under 35MB.
    @discardableResult
    func runMemoryStressCheck(iterations: Int = 100) -> Bool {
        // Warm up caches on initial call
        _ = fetchSwitchableWindows(includeThumbnails: false)
        let baselineMB = Self.currentResidentMemoryMB()

        for _ in 0..<iterations {
            autoreleasepool {
                let windows = fetchSwitchableWindows(includeThumbnails: false)
                _ = windows.count
            }
        }

        let afterMB = Self.currentResidentMemoryMB()
        let deltaMB = afterMB - baselineMB
        return afterMB < 35.0 && deltaMB < 5.0
    }
}
