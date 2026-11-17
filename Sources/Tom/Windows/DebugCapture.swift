import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

/// TOM_DEBUG only: capture our own windows as the window server composites them (no permission needed).
enum DebugCapture {
    static func captureOwnWindows(to dir: String) {
        Task {
            do {
                let content = try await SCShareableContent.currentProcess
                print("windows:", content.windows.map { "\($0.frame) on=\($0.isOnScreen)" })
                for (i, w) in content.windows.enumerated() where w.isOnScreen && w.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier {
                  do {
                    let cfg = SCStreamConfiguration()
                    cfg.width = Int(w.frame.width * 2)
                    cfg.height = Int(w.frame.height * 2)
                    cfg.showsCursor = false
                    cfg.ignoreShadowsSingleWindow = true
                    let img = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: w), configuration: cfg)
                    let path = "\(dir)/win\(i)-\(Int(w.frame.width))x\(Int(w.frame.height)).png"
                    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
                    CGImageDestinationAddImage(dest, img, nil)
                    CGImageDestinationFinalize(dest)
                    print("captured \(path) layer=\(w.windowLayer) frame=\(w.frame)")
                  } catch { print("window \(i) failed: \(error)") }
                }
            } catch {
                print("capture failed: \(error)")
            }
            fflush(stdout)
        }
    }
}

