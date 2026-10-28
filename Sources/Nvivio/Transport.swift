import Foundation

/// What the server answered, or that it could not be reached.
enum Reply: Sendable, Equatable {
    case status(Int, Data)
    case unreachable(String)
}

/// Sends one request. URLSession in the app; tests answer by hand.
protocol Transport: Sendable {
    func post(_ body: Data, to url: URL, done: @escaping @Sendable (Reply) -> Void)
}

/// The time and the timers. Time comes from `Date()`: no uptime or other required-reason API.
/// Tests move it on by hand, so the 10-second wait and the backoff need no waiting.
protocol WallClock: Sendable {
    func now() -> Date
    /// Runs `work` on `queue` after `seconds`.
    func after(_ seconds: TimeInterval, on queue: DispatchQueue, _ work: @escaping @Sendable () -> Void)
}

struct SystemClock: WallClock {
    func now() -> Date { Date() }

    func after(_ seconds: TimeInterval, on queue: DispatchQueue, _ work: @escaping @Sendable () -> Void) {
        queue.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

struct URLSessionTransport: Transport {
    /// Ephemeral, without cookies or cache: nothing of a request is kept, on disk or in memory.
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    /// The server takes only a user agent that starts with `Nvivio-<Platform>/<version>` for an app.
    static func request(_ body: Data, to url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Nvivio-iOS/\(Nvivio.version)", forHTTPHeaderField: "User-Agent")
        return request
    }

    func post(_ body: Data, to url: URL, done: @escaping @Sendable (Reply) -> Void) {
        session.dataTask(with: Self.request(body, to: url)) { data, response, error in
            if let http = response as? HTTPURLResponse {
                done(.status(http.statusCode, data ?? Data()))
            } else {
                done(.unreachable(error?.localizedDescription ?? "no answer"))
            }
        }.resume()
    }
}
