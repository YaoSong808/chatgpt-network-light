import AppKit

if CommandLine.arguments.contains("--probe-once") {
    Task {
        let result = await WebsiteProbe.run()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(result), let json = String(data: data, encoding: .utf8) { print(json) }
        exit(result.state == .reachable ? 0 : result.state == .uncertain ? 2 : 1)
    }
    RunLoop.main.run()
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
