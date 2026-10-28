import Foundation

/// An event waiting in memory to be sent.
struct Pending: Sendable, Equatable {
    /// `pv` (screen view), `en` (time on a screen) or a custom name.
    var name: String
    /// The screen; `en` goes without, it belongs to its screen view.
    var screen: String?
    /// The screen view's id.
    var view: String
    var props: [String: NvivioValue]?
    /// `en`: whole seconds in the foreground.
    var seconds: Int?
    /// `pv`: the deep link's utm_* parameters.
    var campaign: [String: String]?
    var at: Date
}

/// The device and app, as sent with every request.
struct Device: Sendable, Equatable {
    var app: String
    var version: String?
    var os: String
    var kind: String
    var width: Int?
    var language: String?
    /// The hardware model code ("iPhone14,5"); the server names it and never uses it to recognise anyone.
    var model: String? = nil
}

/// One request's body (sdks/PROTOCOL.md): what is the same for every event once, then 1 to 20 events.
struct Batch: Encodable {
    var site: String
    var device: Device
    var launch: String
    var events: [Item]

    struct Item: Encodable {
        var n: String
        var u: String?
        var i: String
        var p: [String: NvivioValue]?
        var d: Int?
        /// Seconds since it happened, counted when the request leaves.
        var g: Int
        var q: [String: String]?
    }

    init(site: String, device: Device, launch: String, events: [Pending], now: Date) {
        self.site = site
        self.device = device
        self.launch = launch
        self.events = events.map {
            Item(n: $0.name, u: $0.screen, i: $0.view, p: $0.props, d: $0.seconds,
                 g: max(0, Int(now.timeIntervalSince($0.at))), q: $0.campaign)
        }
    }

    private enum Keys: String, CodingKey { case s, a, v, o, m, w, l, h, k, e }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(site, forKey: .s)
        try c.encode(device.app, forKey: .a)
        try c.encodeIfPresent(device.version, forKey: .v)
        try c.encode(device.os, forKey: .o)
        try c.encode(device.kind, forKey: .m)
        try c.encodeIfPresent(device.width, forKey: .w)
        try c.encodeIfPresent(device.language, forKey: .l)
        try c.encodeIfPresent(device.model, forKey: .h)
        try c.encode(launch, forKey: .k)
        try c.encode(events, forKey: .e)
    }
}
