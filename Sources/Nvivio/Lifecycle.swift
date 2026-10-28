import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The SDK's link with the app: the device fields and going to the background and back.
/// UIKit and AppKit want the main actor for both; it is a handful of reads, once.
@MainActor
enum Lifecycle {
    private static var attached = false

    static func attach(_ tracker: Tracker) {
        guard !attached else { return }
        attached = true
        if let device = Device.current() {
            tracker.use(device)
        } else {
            tracker.log("The app has no bundle ID; Nvivio sends nothing.")
        }
        let center = NotificationCenter.default
        #if canImport(UIKit)
        _ = center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let task = BackgroundTask()
                tracker.enterBackground { Task { @MainActor in task.end() } }
            }
        }
        _ = center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            tracker.enterForeground()
        }
        #elseif canImport(AppKit)
        // A Mac app is "in the background" while another app is active.
        _ = center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            tracker.enterBackground {}
        }
        _ = center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            tracker.enterForeground()
        }
        #endif
    }
}

#if canImport(UIKit)
/// Keeps the app running until the last request has left, or until iOS says time is up.
@MainActor
private final class BackgroundTask {
    private var id = UIBackgroundTaskIdentifier.invalid

    init() {
        id = UIApplication.shared.beginBackgroundTask(withName: "Nvivio") { self.end() }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
#endif

extension Device {
    @MainActor
    static func current() -> Device? {
        guard let app = Bundle.main.bundleIdentifier else { return nil }
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            .map { String($0.prefix(32)) }
        #if canImport(UIKit)
        let device = UIDevice.current
        let os = "\(device.systemName) \(device.systemVersion)"
        let kind = switch device.userInterfaceIdiom {
        case .phone: "phone"
        case .pad: "tablet"
        default: "desktop"
        }
        #if os(visionOS)
        let width: Int? = nil  // no screen to speak of
        #else
        // Deprecated from iOS 26 for a scene's screen, but no scene is connected yet when an app
        // starts the SDK, and the width is the same.
        let size = UIScreen.main.bounds.size
        let width: Int? = Int(min(size.width, size.height))
        #endif
        #elseif canImport(AppKit)
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let os = "macOS \(system.majorVersion).\(system.minorVersion)"
        let kind = "desktop"
        let width = NSScreen.main.map { Int(min($0.frame.width, $0.frame.height)) }
        #endif
        return Device(app: app, version: version, os: os, kind: kind, width: width,
                      language: Locale.preferredLanguages.first, model: modelCode())
    }

    /// The hardware model code, such as "iPhone14,5" (in the Simulator, the simulated device's),
    /// to show which phones people use. `uname` is not one of Apple's required-reason APIs; the
    /// code is never used to recognise anyone (sdks/PROTOCOL.md).
    static func modelCode() -> String? {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !simulated.isEmpty {
            return simulated
        }
        var info = utsname()
        guard uname(&info) == 0 else { return nil }
        let code = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return code.isEmpty ? nil : String(code.prefix(60))
    }
}
