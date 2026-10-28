import Foundation
import os

/// The SDK's engine (sdks/PROTOCOL.md). All its state lives on `queue`: a public call only
/// notes the time and hops onto it, so it never blocks and never works on the caller's thread.
final class Tracker: @unchecked Sendable {
    static let batchSize = 20
    static let batchDelay: TimeInterval = 10
    static let maxAge: TimeInterval = 3600
    static let maxWaiting = 200
    /// How long the next try waits after the 1st, 2nd, … failed request in a row.
    static let backoff: [TimeInterval] = [10, 30, 60, 120, 240, 300]

    let queue = DispatchQueue(label: "com.nvivio")
    /// Made once per process and kept in memory only: it keeps one launch together when the
    /// IP address changes, and is gone with the process.
    let launch = Tracker.randomID(16)

    private let clock: any WallClock
    private let transport: any Transport
    private let logger = Logger(subsystem: "com.nvivio", category: "Nvivio")
    private let enabled = Locked(true)
    private let debugging = Locked(false)

    private struct Screen {
        var name: String
        var view: String
        /// Since when it counts as seen: nil while the app is in the background.
        var since: Date?
    }

    // On `queue` only.
    private var site: String?
    private var endpoint = Nvivio.defaultEndpoint
    private var device: Device?
    private var waiting: [Pending] = []
    private var sending: [Pending] = []
    private var current: Screen?
    private var campaign: [String: String]?
    private var inBackground = false
    private var timerDue: Date?
    private var timerGeneration = 0
    private var failures = 0
    private var retryAt: Date?
    private var backgroundDone: [@Sendable () -> Void] = []
    private var toldSetupError = false

    init(clock: any WallClock = SystemClock(), transport: any Transport = URLSessionTransport()) {
        self.clock = clock
        self.transport = transport
    }

    // MARK: Calls from the app, any thread

    var isEnabled: Bool {
        get { enabled.value }
        set {
            enabled.value = newValue
            if !newValue { queue.async { self.forget() } }
        }
    }

    var debug: Bool {
        get { debugging.value }
        set { debugging.value = newValue }
    }

    func start(site: String, endpoint: URL) {
        queue.async {
            self.site = site
            self.endpoint = endpoint
            self.plan()
        }
    }

    func use(_ device: Device) {
        queue.async {
            self.device = device
            self.plan()
        }
    }

    func screen(_ name: String) {
        let now = clock.now()
        queue.async { self.show(name, at: now) }
    }

    func event(_ name: String, _ props: [String: NvivioValue] = [:]) {
        let now = clock.now()
        queue.async { self.track(name, props, at: now) }
    }

    func open(_ url: URL) {
        let utm = Self.campaign(of: url)
        queue.async {
            if self.isEnabled { self.campaign = utm }
        }
    }

    /// Sends the current screen's time and everything that waits; `done` once nothing is on its way.
    func enterBackground(_ done: @escaping @Sendable () -> Void) {
        let now = clock.now()
        queue.async {
            self.inBackground = true
            self.pause(at: now)
            self.backgroundDone.append(done)
            self.send()
            self.finishBackground()
        }
    }

    /// The current screen counts on, without a new screen view.
    func enterForeground() {
        let now = clock.now()
        queue.async {
            self.inBackground = false
            self.current?.since = now
        }
    }

    func log(_ message: @autoclosure () -> String) {
        guard debug else { return }
        let text = message()
        logger.notice("\(text, privacy: .public)")
    }

    // MARK: Events

    private func show(_ raw: String, at now: Date) {
        guard isEnabled else { return }
        let name = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard !name.isEmpty else { return log("Nvivio.screen needs a name.") }
        guard name != current?.name else { return }
        pause(at: now)
        let view = Self.randomID(8)
        current = Screen(name: name, view: view, since: inBackground ? nil : now)
        add(Pending(name: "pv", screen: name, view: view, campaign: campaign, at: now))
        campaign = nil
    }

    /// The current screen's time in the foreground since it was shown or the app came back,
    /// when that is a second or more.
    private func pause(at now: Date) {
        guard let screen = current, let since = screen.since else { return }
        current?.since = nil
        let seconds = Int(now.timeIntervalSince(since))
        if seconds >= 1 {
            add(Pending(name: "en", view: screen.view, seconds: seconds, at: now))
        }
    }

    private func track(_ name: String, _ props: [String: NvivioValue], at now: Date) {
        guard isEnabled else { return }
        guard (1...64).contains(name.count), Self.isPlain(name, also: "_.:- "), !Self.reserved.contains(name) else {
            return log("Event \"\(name)\" left out: use letters, digits, spaces and _ . : -, at most 64 characters; pv, en, pageview, engagement and ln are reserved.")
        }
        guard let screen = current else {
            return log("Event \"\(name)\" left out: an event belongs to a screen, call Nvivio.screen first.")
        }
        add(Pending(name: name, screen: screen.name, view: screen.view, props: cleaned(props, of: name), at: now))
    }

    private static let reserved: Set = ["pv", "en", "pageview", "engagement", "ln"]

    /// What the server keeps: up to 20 properties, keys of [A-Za-z0-9_.-] up to 40 characters,
    /// texts up to 200 characters, and numbers JSON can carry.
    private func cleaned(_ props: [String: NvivioValue], of event: String) -> [String: NvivioValue]? {
        var kept: [String: NvivioValue] = [:]
        for (key, value) in props.sorted(by: { $0.key < $1.key }) {
            guard kept.count < 20, (1...40).contains(key.count), Self.isPlain(key, also: "_.-") else { continue }
            switch value {
            case .double(let number) where !number.isFinite: continue
            case .string(let text): kept[key] = .string(String(text.prefix(200)))
            default: kept[key] = value
            }
        }
        if kept.count < props.count {
            log("Event \"\(event)\": \(props.count - kept.count) properties left out (at most 20, keys of A-Z a-z 0-9 _ . - up to 40 characters, finite numbers).")
        }
        return kept.isEmpty ? nil : kept
    }

    private static let utmKeys: Set = ["utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content"]

    static func campaign(of url: URL) -> [String: String]? {
        var utm: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] where utmKeys.contains(item.name) {
            if let value = item.value?.trimmingCharacters(in: .whitespaces), !value.isEmpty {
                utm[item.name] = String(value.prefix(200))
            }
        }
        return utm.isEmpty ? nil : utm
    }

    private func add(_ event: Pending) {
        waiting.append(event)
        trim()
        plan()
    }

    /// At most 200 events wait; beyond that the oldest go first.
    private func trim() {
        if waiting.count > Self.maxWaiting { waiting.removeFirst(waiting.count - Self.maxWaiting) }
    }

    /// Opted out: what waits and the current screen go, so nothing from before turns up later.
    private func forget() {
        waiting = []
        current = nil
        campaign = nil
        retryAt = nil
        failures = 0
        disarm()
    }

    // MARK: Sending

    /// When the next request leaves: at once when 20 wait, else 10 seconds after the first one
    /// started waiting, and after a failed request not before its backoff ends.
    private func plan() {
        guard !waiting.isEmpty, sending.isEmpty, site != nil, device != nil else { return }
        if let retryAt {
            if timerDue != retryAt { wake(at: retryAt) }
        } else if waiting.count >= Self.batchSize {
            send()
        } else if timerDue == nil {
            wake(at: clock.now() + Self.batchDelay)
        }
    }

    private func wake(at due: Date) {
        timerGeneration += 1
        let generation = timerGeneration
        timerDue = due
        clock.after(max(0, due.timeIntervalSince(clock.now())), on: queue) {
            guard generation == self.timerGeneration else { return }
            self.timerDue = nil
            self.send()
        }
    }

    private func disarm() {
        timerGeneration += 1
        timerDue = nil
    }

    /// One request with the oldest 20 that wait; `g` is counted now, so a retried event keeps its real age.
    private func send() {
        guard sending.isEmpty, isEnabled, let site, let device else { return }
        let now = clock.now()
        waiting.removeAll { now.timeIntervalSince($0.at) > Self.maxAge }
        guard !waiting.isEmpty else { return }
        disarm()
        sending = Array(waiting.prefix(Self.batchSize))
        waiting.removeFirst(sending.count)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        guard let body = try? encoder.encode(Batch(site: site, device: device, launch: launch, events: sending, now: now)) else {
            log("Could not encode \(sending.count) events; they are left out.")
            sending = []
            return
        }
        log("→ \(endpoint.absoluteString) \(String(decoding: body, as: UTF8.self))")
        transport.post(body, to: endpoint) { reply in
            self.queue.async { self.answered(reply) }
        }
    }

    private func answered(_ reply: Reply) {
        let batch = sending
        sending = []
        var retrying = false
        switch reply {
        case .status(let status, _) where (200..<300).contains(status):
            log("← \(status)")
            failures = 0
            retryAt = nil
        case .status(let status, let body) where [400, 403, 404].contains(status):
            // A setup error (unknown site, app not listed, invalid events) that sending the same
            // again cannot fix. The server says what to do.
            let problem = Self.problem(in: body)
            if debug || !toldSetupError {
                logger.error("Nvivio answered \(status): \(problem, privacy: .public)")
            }
            toldSetupError = true
        case .status(let status, _):
            // 429, 5xx, or anything unexpected (a Wi-Fi login page in the way): the events wait.
            retrying = true
            retry(batch, after: "\(status)")
        case .unreachable(let reason):
            retrying = true
            retry(batch, after: reason)
        }
        if !backgroundDone.isEmpty {
            if !retrying { send() }  // the rest, while iOS still gives the app time
            finishBackground()
        }
        plan()
    }

    /// Network error, 429, 5xx or another unexpected answer: the events wait again, in front, and the next try backs off.
    private func retry(_ batch: [Pending], after reason: String) {
        guard isEnabled else { return }
        waiting = batch + waiting
        trim()
        failures += 1
        let delay = Self.backoff[min(failures, Self.backoff.count) - 1]
        retryAt = clock.now() + delay
        log("← \(reason): \(batch.count) events wait, next try in \(Int(delay)) s")
    }

    /// Lets the app suspend once nothing is on its way.
    private func finishBackground() {
        guard sending.isEmpty else { return }
        let done = backgroundDone
        backgroundDone = []
        done.forEach { $0() }
    }

    private static func problem(in body: Data) -> String {
        struct Problem: Decodable { var error: String?; var fix: String? }
        guard let problem = try? JSONDecoder().decode(Problem.self, from: body) else {
            return String(decoding: body.prefix(300), as: UTF8.self)
        }
        return [problem.error, problem.fix].compactMap { $0 }.joined(separator: " ")
    }

    // MARK: Helpers

    /// ASCII letters and digits plus `extra`: what the server's patterns allow.
    private static func isPlain(_ text: String, also extra: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
                || extra.unicodeScalars.contains(scalar)
        }
    }

    static func randomID(_ length: Int) -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).map { _ in characters.randomElement()! })
    }
}

/// A value any thread may read and write.
final class Locked<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}
