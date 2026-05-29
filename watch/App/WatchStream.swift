import SwiftUI

/// Pulls JPEG frames from mactesla's `/frame` endpoint in a polling loop.
/// We use plain HTTP GET instead of WebSocket because URLSessionWebSocketTask
/// is blocked on watchOS 26.x for personal-team-signed apps.
@MainActor
final class WatchStream: ObservableObject {
    @Published var image: UIImage?
    @Published var status: String = "끊김"
    @Published var fps: Int = 0

    private var lastHost: String = ""
    private var pollTask: Task<Void, Never>?
    private var frameCount: Int = 0
    private var tickStart: Date = Date()

    /// Polling interval between frame requests (ms). Lower = higher fps but more
    /// network/CPU overhead. 33ms ≈ 30fps target on LAN.
    private let pollIntervalMs: UInt64 = 33

    func connect(to host: String) {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { status = "주소 없음"; return }
        lastHost = trimmed

        // Cancel any existing poll loop.
        pollTask?.cancel()
        pollTask = nil

        status = "연결 중…"
        image = nil
        frameCount = 0
        tickStart = Date()
        fps = 0

        pollTask = Task { @MainActor [weak self] in
            await self?.pollLoop(trimmed)
        }
    }

    private func pollLoop(_ host: String) async {
        // Resolve once at the start: HEAD-follow for short URLs, then build HTTP base URL.
        let baseURLString = await resolveBase(host)
        guard let frameURL = URL(string: baseURLString.hasSuffix("/")
                                 ? "\(baseURLString)frame"
                                 : "\(baseURLString)/frame") else {
            status = "주소 오류"
            return
        }

        var consecutiveErrors = 0
        while !Task.isCancelled {
            let session = freshSession()
            var req = URLRequest(url: frameURL)
            req.httpMethod = "GET"
            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

            do {
                let (data, response) = try await session.data(for: req)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    status = "HTTP \(code)"
                    consecutiveErrors += 1
                    try? await Task.sleep(nanoseconds: backoffNanos(consecutiveErrors))
                    continue
                }
                if let img = UIImage(data: data) {
                    image = img
                    if status != "연결됨" { status = "연결됨" }
                    frameCount += 1
                    let dt = Date().timeIntervalSince(tickStart)
                    if dt >= 1 {
                        fps = Int(Double(frameCount) / dt)
                        frameCount = 0
                        tickStart = Date()
                    }
                }
                consecutiveErrors = 0
                try? await Task.sleep(nanoseconds: pollIntervalMs * 1_000_000)
            } catch {
                let ns = error as NSError
                status = "에러: \(ns.code) \(ns.localizedDescription.prefix(60))"
                consecutiveErrors += 1
                try? await Task.sleep(nanoseconds: backoffNanos(consecutiveErrors))
            }
        }
    }

    private func backoffNanos(_ tries: Int) -> UInt64 {
        // 500ms → 1s → 2s → 4s (cap)
        let cap = 4
        let n = min(tries, cap)
        return UInt64(500_000_000) * UInt64(1 << (n - 1))
    }

    private func freshSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = true
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }

    /// Convert user host input to an http(s) base URL string (without trailing path).
    /// Follows redirects for short URLs.
    private func resolveBase(_ input: String) async -> String {
        let http: String
        if input.hasPrefix("http://") || input.hasPrefix("https://") {
            http = input
        } else if input.hasPrefix("ws://") {
            http = "http://" + input.dropFirst("ws://".count)
        } else if input.hasPrefix("wss://") {
            http = "https://" + input.dropFirst("wss://".count)
        } else {
            http = "http://\(input)"
        }
        guard let url = URL(string: http) else { return http }
        // Follow redirects via HEAD (short URLs like spoo.me).
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 8
        do {
            let (_, response) = try await freshSession().data(for: req)
            if let resolved = (response as? HTTPURLResponse)?.url {
                let s = resolved.absoluteString
                // Strip any trailing path so we can append /frame later.
                if let r = s.range(of: "://"), let pathStart = s.range(of: "/", range: r.upperBound..<s.endIndex) {
                    return String(s[..<pathStart.lowerBound])
                }
                return s
            }
        } catch { /* fall through */ }
        return http
    }
}
