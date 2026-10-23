import Foundation
import Network
import Combine

// Reachability ported from TopMenu's NetworkStatePlugin (NWPathMonitor). The speed test follows
// WifiDiag's SpeedTestManager: warm-up, latency probes, parallel time-bounded streams, and a
// ramp-up window excluded from the figure, against Cloudflare's speed endpoints.
// Reachability is informational only: a satisfied path is not proof of working internet.

nonisolated enum SpeedMath {
    static func megabitsPerSecond(bytes: Int, duration: TimeInterval) -> Double? {
        guard bytes > 0, duration > 0 else { return nil }
        return (Double(bytes) * 8 / duration) / 1_000_000
    }
    /// Bytes counted after the ramp-up window over the time that window left.
    static func aggregate(bytesAfterRamp: Int64, elapsed: TimeInterval, rampUp: TimeInterval) -> Double? {
        megabitsPerSecond(bytes: Int(clamping: bytesAfterRamp), duration: elapsed - rampUp)
    }
    /// Mean after dropping the top and bottom 10 percent, as Cloudflare does for latency.
    static func trimmedMean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let trim = sorted.count >= 10 ? sorted.count / 10 : 0
        let kept = sorted.dropFirst(trim).dropLast(trim)
        return kept.reduce(0, +) / Double(kept.count)
    }
    static func label(download: Double?, upload: Double?, latencyMs: Double? = nil) -> String {
        var parts: [String] = []
        if let download { parts.append(String(format: "%.1f Mbps down", download)) }
        if let upload { parts.append(String(format: "%.1f Mbps up", upload)) }
        if let latencyMs { parts.append(String(format: "%.0f ms", latencyMs)) }
        return parts.isEmpty ? "Not measured" : parts.joined(separator: " · ")
    }
    static func formattedSeconds(_ seconds: Double) -> String {
        seconds == seconds.rounded() ? "\(Int(seconds)) s" : String(format: "%.1f s", seconds)
    }
    static func reachabilityLabel(_ reachable: Bool?) -> String {
        switch reachable { case nil: "Checking…"; case true?: "Online"; case false?: "Offline" }
    }
}

nonisolated enum SpeedTest {
    static let base = "https://speed.cloudflare.com"
    static let probeURL = URL(string: base + "/__down?bytes=1")!
    static let uploadURL = URL(string: base + "/__up")!
    static let downloadURL = URL(string: base + "/__down?bytes=250000000")!
    static let downloadStreams = 6
    static let uploadStreams = 8
    static let streamStagger: TimeInterval = 0.3
    static let downloadRampUp: TimeInterval = 0.5
    static let latencyProbes = 10
    static let minChunk = 256 * 1024
    static let maxChunk = 8 * 1024 * 1024
    static let targetChunkSeconds = 1.5

    actor ByteCounter {
        private(set) var total: Int64 = 0
        private(set) var afterRamp: Int64 = 0
        func add(_ bytes: Int, afterRamp inWindow: Bool) {
            total &+= Int64(bytes)
            if inWindow { afterRamp &+= Int64(bytes) }
        }
    }

    /// Cloudflare answers 403 to large `__down` requests without browser-style headers (100 MB and up
    /// at the time of writing); WifiDiag sends the same two headers for the same reason.
    static func request(_ url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(base, forHTTPHeaderField: "Origin")
        request.setValue(base + "/", forHTTPHeaderField: "Referer")
        return request
    }

    static func seconds(since start: ContinuousClock.Instant) -> TimeInterval {
        let parts = start.duration(to: .now).components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }

    static func session(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: configuration)
    }

    /// Warm-up establishes TLS and HTTP/2 so the first probe is not charged the handshake.
    static func latency() async -> Double? {
        let session = session(timeout: 3)
        defer { session.invalidateAndCancel() }
        _ = try? await session.data(for: request(probeURL))
        var samples: [Double] = []
        for _ in 0..<latencyProbes {
            let start = ContinuousClock.now
            if let (_, response) = try? await session.data(for: request(probeURL)),
               (response as? HTTPURLResponse).map({ (200..<400).contains($0.statusCode) }) == true {
                samples.append(seconds(since: start) * 1000)
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return SpeedMath.trimmedMean(samples)
    }

    struct StreamResult: Sendable { var total: Int64 = 0; var afterRamp: Int64 = 0; var error: String? }

    static func download(seconds duration: TimeInterval) async -> (speed: Double?, error: String?) {
        let start = ContinuousClock.now
        var total: Int64 = 0, afterRamp: Int64 = 0
        var errors: [String] = []
        await withTaskGroup(of: StreamResult.self) { group in
            for index in 0..<downloadStreams {
                group.addTask {
                    try? await Task.sleep(nanoseconds: UInt64(Double(index) * streamStagger * 1e9))
                    return await downloadStream(duration: duration, start: start)
                }
            }
            for await result in group {
                total &+= result.total; afterRamp &+= result.afterRamp
                if let error = result.error { errors.append(error) }
            }
        }
        guard total > 0 else { return (nil, "Download: " + (errors.first ?? "no data received")) }
        return (SpeedMath.aggregate(bytesAfterRamp: afterRamp, elapsed: seconds(since: start), rampUp: downloadRampUp), nil)
    }

    /// Byte counting happens synchronously on the session's delegate queue; spawning a task per
    /// callback left thousands of updates pending when the totals were read.
    private static func downloadStream(duration: TimeInterval, start: ContinuousClock.Instant) async -> StreamResult {
        let delegate = StreamDelegate()
        let session = URLSession(configuration: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
            configuration.timeoutIntervalForRequest = duration + 15
            configuration.timeoutIntervalForResource = duration + 30
            return configuration
        }(), delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: request(downloadURL))
        delegate.onBytes = { bytes in
            let elapsed = seconds(since: start)
            if elapsed >= duration { task.cancel(); return }
            if elapsed > downloadRampUp { delegate.afterRampBytes += bytes }
        }
        let completion: Error? = await withCheckedContinuation { continuation in
            delegate.onDone = { continuation.resume(returning: $0) }
            task.resume()
        }
        var result = StreamResult(total: Int64(delegate.receivedBytes), afterRamp: Int64(delegate.afterRampBytes))
        if let completion, (completion as? URLError)?.code != .cancelled, delegate.receivedBytes == 0 { result.error = completion.localizedDescription }
        if let code = delegate.statusCode, code >= 400 {
            // An error body is not throughput.
            result = StreamResult(total: 0, afterRamp: 0, error: "HTTP \(code)")
        }
        return result
    }

    /// Each stream gets its own session, and so its own TCP connection: one multiplexed HTTP/2
    /// connection collapses on every Wi-Fi loss and under-reports the link.
    static func upload(seconds duration: TimeInterval) async -> (speed: Double?, error: String?) {
        let rampUp = min(2, duration * 0.3)
        let counter = ByteCounter()
        let start = ContinuousClock.now
        let payload = Data(repeating: 0xAB, count: maxChunk)
        var errors: [String] = []
        await withTaskGroup(of: String?.self) { group in
            for index in 0..<uploadStreams {
                group.addTask {
                    try? await Task.sleep(nanoseconds: UInt64(Double(index) * streamStagger * 1e9))
                    let session = session(timeout: 20)
                    defer { session.invalidateAndCancel() }
                    var chunk = minChunk
                    var lastError: String?
                    while seconds(since: start) < duration {
                        var request = request(uploadURL, method: "POST")
                        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                        let chunkStart = ContinuousClock.now
                        do {
                            let (_, response) = try await session.upload(for: request, from: payload.prefix(chunk))
                            guard let code = (response as? HTTPURLResponse)?.statusCode, code < 400 else {
                                lastError = "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"; break
                            }
                            let took = max(0.001, seconds(since: chunkStart))
                            await counter.add(chunk, afterRamp: seconds(since: start) > rampUp)
                            // Next chunk: about targetChunkSeconds of traffic at the rate just seen.
                            chunk = min(maxChunk, max(minChunk, Int(Double(chunk) / took * targetChunkSeconds)))
                        } catch {
                            lastError = error.localizedDescription; break
                        }
                    }
                    return lastError
                }
            }
            for await error in group { if let error { errors.append(error) } }
        }
        let total = await counter.total, afterRamp = await counter.afterRamp
        guard total > 0 else { return (nil, "Upload: " + (errors.first ?? "nothing sent")) }
        return (SpeedMath.aggregate(bytesAfterRamp: afterRamp, elapsed: seconds(since: start), rampUp: rampUp), nil)
    }

    final class StreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        var onBytes: (@Sendable (Int) -> Void)?
        var onDone: (@Sendable (Error?) -> Void)?
        private(set) var receivedBytes = 0
        var afterRampBytes = 0
        private(set) var statusCode: Int?
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            statusCode = (response as? HTTPURLResponse)?.statusCode
            completionHandler(.allow)
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            receivedBytes += data.count
            onBytes?(data.count)
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            onDone?(error); onDone = nil
        }
    }
}

@MainActor final class InternetService: ObservableObject {
    @Published private(set) var reachable: Bool?
    @Published private(set) var download: Double?
    @Published private(set) var upload: Double?
    @Published private(set) var latencyMs: Double?
    @Published private(set) var measuredAt: Date?
    @Published private(set) var failure: String?
    @Published private(set) var testing = false
    @Published private(set) var phase = ""
    private let monitor = NWPathMonitor()

    var reachabilityStatus: HealthStatus {
        switch reachable { case nil: .unknown; case true?: .good; case false?: .attention }
    }
    var speedLabel: String { SpeedMath.label(download: download, upload: upload, latencyMs: latencyMs) }

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in self?.reachable = satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "ITHub.InternetReachability"))
    }
    deinit { monitor.cancel() }

    /// Each phase runs for `seconds` at full link rate: a 5-second test on a 200/40 Mbps link moves about 150 MB.
    func runSpeedTest(seconds: Double) {
        guard !testing else { return }
        testing = true; failure = nil
        Task {
            phase = "Latency"
            latencyMs = await SpeedTest.latency()
            phase = "Download"
            let down = await SpeedTest.download(seconds: seconds)
            phase = "Upload"
            let up = await SpeedTest.upload(seconds: seconds)
            download = down.speed; upload = up.speed
            failure = down.error ?? up.error
            measuredAt = Date(); testing = false; phase = ""
        }
    }
}
