import Foundation
@testable import Nvivio

/// Time that moves only when a test says so; timers run on their queue when they come due.
final class TestClock: WallClock, @unchecked Sendable {
    private typealias Timer = (due: Date, queue: DispatchQueue, work: @Sendable () -> Void)
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    private var timers: [Timer] = []

    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func after(_ seconds: TimeInterval, on queue: DispatchQueue, _ work: @escaping @Sendable () -> Void) {
        lock.lock(); defer { lock.unlock() }
        timers.append((current + seconds, queue, work))
    }

    func advance(_ seconds: TimeInterval) {
        let end = now() + seconds
        while let timer = nextTimer(dueBy: end) {
            timer.queue.sync(execute: timer.work)
        }
        lock.lock(); defer { lock.unlock() }
        current = end
    }

    /// The earliest timer due by `end`, with the time set to its deadline.
    private func nextTimer(dueBy end: Date) -> Timer? {
        lock.lock(); defer { lock.unlock() }
        guard let index = timers.indices.filter({ timers[$0].due <= end }).min(by: { timers[$0].due < timers[$1].due }) else {
            return nil
        }
        let timer = timers.remove(at: index)
        current = max(current, timer.due)
        return timer
    }
}

/// Keeps every request; the test answers them one by one, oldest first.
final class TestTransport: Transport, @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [Data] = []
    private var open: [@Sendable (Reply) -> Void] = []

    func post(_ body: Data, to url: URL, done: @escaping @Sendable (Reply) -> Void) {
        lock.lock(); defer { lock.unlock() }
        bodies.append(body)
        open.append(done)
    }

    var sent: [Data] {
        lock.lock(); defer { lock.unlock() }
        return bodies
    }

    var unanswered: Int {
        lock.lock(); defer { lock.unlock() }
        return open.count
    }

    func answer(_ reply: Reply) {
        lock.lock()
        let done = open.removeFirst()
        lock.unlock()
        done(reply)
    }
}

/// A tracker with a test clock and transport, started for a phone unless asked otherwise.
struct Harness {
    let clock = TestClock()
    let transport = TestTransport()
    let tracker: Tracker

    init(started: Bool = true) {
        tracker = Tracker(clock: clock, transport: transport)
        if started { start() }
    }

    func start() {
        tracker.start(site: "NV-6T78AE8", endpoint: URL(string: "https://nviv.io/a")!)
        tracker.use(Device(app: "com.acme.shop", version: "2.3.1", os: "iOS 26.1", kind: "phone", width: 402, language: "nl-BE", model: "iPhone14,5"))
        settle()
    }

    /// Waits until the tracker's queue has done everything asked of it so far.
    func settle() {
        tracker.queue.sync {}
    }

    func advance(_ seconds: TimeInterval) {
        settle()
        clock.advance(seconds)
        settle()
    }

    func answer(_ reply: Reply) {
        settle()
        transport.answer(reply)
        settle()
    }

    static let delivered = Reply.status(204, Data())

    var batches: [SentBatch] {
        settle()
        return transport.sent.map { try! JSONDecoder().decode(SentBatch.self, from: $0) }
    }
}

/// A request body as the server reads it.
struct SentBatch: Decodable {
    var s: String
    var a: String
    var v: String?
    var o: String?
    var m: String?
    var w: Int?
    var l: String?
    var h: String?
    var k: String
    var e: [SentEvent]
}

struct SentEvent: Decodable, Equatable {
    var n: String
    var u: String?
    var i: String
    var p: [String: SentValue]?
    var d: Int?
    var g: Int
    var q: [String: String]?
}

/// A property as it is in the JSON: a boolean is no number and a whole number no decimal.
enum SentValue: Decodable, Equatable {
    case bool(Bool), int(Int), double(Double), string(String)

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Int.self) { self = .int(value) }
        else if let value = try? c.decode(Double.self) { self = .double(value) }
        else { self = .string(try c.decode(String.self)) }
    }
}

func isCode(_ text: String, length: Int) -> Bool {
    text.count == length && text.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
}
