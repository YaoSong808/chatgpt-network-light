import Foundation

enum LightState: String, Codable {
    case checking, reachable, unreachable, uncertain
}

struct ProbeResult: Codable {
    let state: LightState
    let title: String
    let detail: String
    let latency: Double?
    let httpStatus: Int?
    let checkedAt: Date

    static func checking(_ detail: String = "正在连接 chatgpt.com") -> ProbeResult {
        ProbeResult(state: .checking, title: "正在检测", detail: detail,
                    latency: nil, httpStatus: nil, checkedAt: Date())
    }
}

enum WebClassifier {
    static func allowed(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "chatgpt.com" || host == "www.chatgpt.com"
    }

    static func classify(response: HTTPURLResponse, body: Data, elapsed: Double) -> ProbeResult {
        let code = response.statusCode
        func result(_ state: LightState, _ title: String, _ detail: String) -> ProbeResult {
            ProbeResult(state: state, title: title, detail: detail,
                        latency: elapsed, httpStatus: code, checkedAt: Date())
        }
        guard allowed(response.url) else {
            return result(.uncertain, "访问被重定向", "未收到 ChatGPT 官网响应，可能需要网络登录")
        }
        let html = String(decoding: body, as: UTF8.self).lowercased()
        let challenge = response.value(forHTTPHeaderField: "cf-mitigated")?.lowercased() == "challenge"
            || html.contains("<title>just a moment")
            || html.contains("<title>attention required")
            || html.contains("<title>verify you are human")
            || html.contains("<title>access denied")
        if challenge || code == 403 || code == 429 {
            return result(.uncertain, "访问受限 / 待验证", "官网已响应，但有拦截、验证或限流；请打开官网确认")
        }
        if (200...299).contains(code) {
            let isHTML = response.mimeType?.lowercased() == "text/html"
            if isHTML && html.contains("chatgpt") && (html.contains("<html") || html.contains("<!doctype html")) {
                return result(.reachable, "ChatGPT 官网可达", "已收到官网页面；桌面端连接可参考此结果")
            }
            return result(.uncertain, "页面无法确认", "收到 HTTP \(code)，但未识别为 ChatGPT 页面")
        }
        if (500...599).contains(code) {
            return result(.unreachable, "官网暂时异常", "ChatGPT 返回 HTTP \(code)，稍后自动重试")
        }
        return result(.uncertain, "官网响应异常", "收到 HTTP \(code)，请打开官网确认")
    }

    static func failed(_ error: Error) -> ProbeResult {
        let ns = error as NSError
        let detail: String
        switch ns.code {
        case NSURLErrorTimedOut: detail = "连接超时，VPN 或路由可能尚未恢复"
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: detail = "DNS 解析失败"
        case NSURLErrorNotConnectedToInternet: detail = "当前网络未连接"
        case NSURLErrorNetworkConnectionLost: detail = "网络连接中断，正在等待恢复"
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid:
            detail = "HTTPS / 证书连接失败"
        case NSURLErrorCannotConnectToHost: detail = "无法连接官网，检查 VPN 或代理状态"
        default: detail = "连接失败（\(ns.domain) / \(ns.code)）"
        }
        return ProbeResult(state: .unreachable, title: "ChatGPT 连接失败", detail: detail,
                           latency: nil, httpStatus: nil, checkedAt: Date())
    }
}

// A redirect must remain on the official HTTPS origin. No login cookies or credentials are sent.
private final class RedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(WebClassifier.allowed(request.url) ? request : nil)
    }
}

enum WebsiteProbe {
    static func run() async -> ProbeResult {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 8
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        // Default proxy handling is retained so macOS VPN / system proxy settings apply.
        let session = URLSession(configuration: configuration, delegate: RedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://chatgpt.com/")!)
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("ChatGPTNetworkLight/1.0 (macOS; connectivity check)", forHTTPHeaderField: "User-Agent")
        let start = Date()
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else {
                return WebClassifier.failed(URLError(.badServerResponse))
            }
            // Bounded reading: never download the complete app or its JavaScript assets.
            var body = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                body.append(byte)
                if body.count >= 65_536 { break }
            }
            return WebClassifier.classify(response: response, body: body, elapsed: Date().timeIntervalSince(start))
        } catch {
            return WebClassifier.failed(error)
        }
    }
}
