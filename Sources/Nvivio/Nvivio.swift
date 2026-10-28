import Foundation

/// Cookieless, privacy-first analytics for your app: screen views, time on a screen and
/// custom events, sent to Nvivio without storing anything on the device and without
/// identifiers, so no consent prompt is needed.
///
/// Every call is cheap and safe from any thread; the work happens on the SDK's own queue.
/// Calls made before ``start(site:endpoint:)`` wait in memory and leave once it is called.
public enum Nvivio {
    /// Nvivio's endpoint for apps.
    public static let defaultEndpoint = URL(string: "https://nviv.io/a")!

    /// The SDK's version, as sent in the user agent.
    static let version = "1.0.0"

    static let tracker = Tracker()

    /// Starts measuring for the site with this code (as in the web script, e.g. "NV-6T78AE8").
    /// The app's bundle ID must be listed in the site's app in Nvivio (Settings › Parts).
    public static func start(site: String, endpoint: URL = defaultEndpoint) {
        tracker.start(site: site, endpoint: endpoint)
        Task { @MainActor in Lifecycle.attach(tracker) }
    }

    /// A screen view. Calling it again for the screen that is already current sends nothing,
    /// so it is safe in `onAppear` or `viewDidAppear`.
    public static func screen(_ name: String) {
        tracker.screen(name)
    }

    /// A custom event on the current screen, with up to 20 properties:
    /// `Nvivio.event("Purchase", ["plan": "pro", "qty": 2, "gift": true])`.
    /// Names hold letters, digits, spaces and `_ . : -`, at most 64 characters.
    public static func event(_ name: String, _ props: [String: NvivioValue] = [:]) {
        tracker.event(name, props)
    }

    /// The deep link or universal link that opened the app: its `utm_*` parameters go
    /// with the next screen view, so campaigns show up as the visit's source.
    public static func open(_ url: URL) {
        tracker.open(url)
    }

    /// Set to `false` when the user opts out: what waits is dropped and nothing is sent
    /// until it is `true` again. Not remembered: keep the user's choice in your own settings.
    public static var isEnabled: Bool {
        get { tracker.isEnabled }
        set { tracker.isEnabled = newValue }
    }

    /// Logs every request and answer (subsystem "com.nvivio", category "Nvivio").
    public static var debug: Bool {
        get { tracker.debug }
        set { tracker.debug = newValue }
    }
}
