import Foundation

@main struct ClassifierTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            guard condition() else { fatalError("FAIL: \(name)") }
            count += 1
            print("PASS: \(name)")
        }
        func classify(_ code: Int = 200, _ body: String = "<!doctype html><html><title>ChatGPT</title></html>",
                      url: String = "https://chatgpt.com/", headers: [String: String] = [:]) -> LightState {
            var fields = headers
            fields["Content-Type"] = fields["Content-Type"] ?? "text/html; charset=utf-8"
            let response = HTTPURLResponse(url: URL(string: url)!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: fields)!
            return WebClassifier.classify(response: response, body: Data(body.utf8), elapsed: 0.2).state
        }
        check(classify() == .reachable, "正常官网 HTML 为绿色")
        check(classify(200, "<!DOCTYPE html><HTML><title>ChatGPT</title></HTML>") == .reachable, "HTML 大小写")
        check(classify(200, "<html><title>Just a moment...</title>chatgpt</html>") == .uncertain, "200 验证页不能误报绿色")
        check(classify(headers: ["cf-mitigated": "challenge"]) == .uncertain, "Cloudflare challenge header")
        check(classify(403) == .uncertain, "403 需要确认")
        check(classify(429) == .uncertain, "限流不能误报网络断开或绿色")
        check(classify(502) == .unreachable, "官网 502 为红色")
        check(classify(401) == .uncertain, "401 不能误报绿色")
        check(classify(302) == .uncertain, "未跟随的重定向不能误报绿色")
        check(classify(200, "<html>请登录 Wi-Fi</html>") == .uncertain, "网络门户不能误报绿色")
        check(classify(200, "", headers: ["Content-Type": "text/html"]) == .uncertain, "空响应不能误报绿色")
        check(classify(headers: ["Content-Type": "application/json"]) == .uncertain, "非 HTML 不能误报绿色")
        check(classify(url: "https://wifi.example/login") == .uncertain, "外部域名不能误报绿色")
        check(!WebClassifier.allowed(URL(string: "http://chatgpt.com/")), "禁止降级为 HTTP")
        check(!WebClassifier.allowed(URL(string: "https://chatgpt.com.evil.example/")), "域名后缀欺骗")
        check(WebClassifier.allowed(URL(string: "https://www.chatgpt.com/")), "允许官网 www 域名")
        check(WebClassifier.failed(URLError(.timedOut)).state == .unreachable, "超时为红色")
        check(WebClassifier.failed(URLError(.cannotFindHost)).detail.contains("DNS"), "DNS 失败说明")
        check(WebClassifier.failed(URLError(.serverCertificateUntrusted)).state == .unreachable, "证书错误不绕过")
        print("\(count) tests passed")
    }
}
