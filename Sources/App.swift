import AppKit
import SwiftUI
import Network
import SystemConfiguration

@MainActor final class Monitor: ObservableObject {
    @Published var result = ProbeResult.checking()
    @Published var checking = false
    var onChange: (() -> Void)?
    private var task: Task<Void, Never>?
    private var timer: Timer?
    private var debounce: Timer?
    private var generation = 0
    private var fastUntil = Date().addingTimeInterval(30)
    private let pathMonitor = NWPathMonitor()
    private var store: SCDynamicStore?
    private var storeSource: CFRunLoopSource?
    private var storeSnapshot: NSDictionary?
    private var pathSignature: String?
    private let storePatterns = ["State:/Network/Global/(IPv4|IPv6|DNS|Proxies)$",
        "State:/Network/Service/[^/]+/(IPv4|IPv6|DNS|Proxies)$",
        "Setup:/Network/Global/Proxies$", "Setup:/Network/Service/[^/]+/Proxies$"] as CFArray
    private var observers: [NSObjectProtocol] = []
    private var sleeping = false
    private(set) var interval: TimeInterval = {
        let value = UserDefaults.standard.double(forKey: "interval")
        return [5.0, 15.0, 30.0].contains(value) ? value : 15
    }()

    func start() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let signature = "\(path.status)|\(path.supportsIPv4)|\(path.supportsIPv6)|\(path.isExpensive)|\(path.availableInterfaces.map { $0.name }.sorted())"
            Task { @MainActor in
                guard let self, signature != self.pathSignature else { return }
                let hadPath = self.pathSignature != nil
                self.pathSignature = signature
                if hadPath { self.networkChanged() }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "net.chatgpt.light.path"))
        var context = SCDynamicStoreContext(version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        store = SCDynamicStoreCreate(nil, "ChatGPTNetworkLight" as CFString, { _, _, info in
            guard let info else { return }
            let monitor = Unmanaged<Monitor>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in monitor.configurationChanged() }
        }, &context)
        if let store {
            SCDynamicStoreSetNotificationKeys(store, nil, storePatterns)
            storeSnapshot = SCDynamicStoreCopyMultiple(store, nil, storePatterns) as NSDictionary?
            storeSource = SCDynamicStoreCreateRunLoopSource(nil, store, 0)
            if let storeSource { CFRunLoopAddSource(CFRunLoopGetMain(), storeSource, .commonModes) }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = false; self?.networkChanged() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = true; self?.cancel(); self?.result = .checking("唤醒后自动重新检测") }
        })
        check()
    }

    private func configurationChanged() {
        guard let store, let snapshot = SCDynamicStoreCopyMultiple(store, nil, storePatterns) as NSDictionary? else { return }
        if let previous = storeSnapshot, snapshot.isEqual(previous) { return }
        storeSnapshot = snapshot
        networkChanged()
    }

    private func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        timer?.invalidate()
        debounce?.invalidate()
        checking = false
    }

    func networkChanged() {
        guard !sleeping else { return }
        // Coalesce bursts without repeatedly postponing the next check.
        guard debounce?.isValid != true else { return }
        cancel()
        fastUntil = Date().addingTimeInterval(30)
        result = .checking("网络发生变化，正在重新检测")
        onChange?()
        debounce = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
    }

    func setInterval(_ value: TimeInterval) {
        interval = value
        UserDefaults.standard.set(value, forKey: "interval")
        check()
    }

    func check() {
        guard !sleeping else { return }
        cancel()
        let token = generation
        checking = true
        // Clear stale green during every new check, including after VPN route changes.
        result = .checking()
        onChange?()
        task = Task { [weak self] in
            let next = await WebsiteProbe.run()
            guard let self, !Task.isCancelled, token == generation else { return }
            result = next
            checking = false
            onChange?()
            let delay = Date() < fastUntil ? 3.0 : interval
            timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.check() }
            }
        }
    }

    func stop() {
        cancel()
        pathMonitor.cancel()
        if let storeSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), storeSource, .commonModes) }
        store = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
    }
}

extension LightState {
    var color: Color {
        switch self {
        case .reachable: return Color(red: 0.22, green: 0.88, blue: 0.60)
        case .unreachable: return Color(red: 1.0, green: 0.33, blue: 0.37)
        case .uncertain: return Color(red: 1.0, green: 0.75, blue: 0.30)
        case .checking: return Color(red: 0.60, green: 0.66, blue: 0.74)
        }
    }
    var symbol: String {
        switch self {
        case .reachable: return "checkmark"
        case .unreachable: return "xmark"
        case .uncertain: return "exclamationmark"
        case .checking: return "ellipsis"
        }
    }
}

struct LocationHintView: View {
    @ObservedObject var monitor: Monitor
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(monitor.result.state.color).frame(width: 7, height: 7)
                Text("ChatGPT 网络灯").font(.system(size: 13, weight: .semibold))
            }
            Text(monitor.result.title).font(.system(size: 12)).foregroundStyle(.secondary)
            Text("小圆灯就在这里，点击可查看详情。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 246, alignment: .leading)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let monitor = Monitor()
    var statusItem: NSStatusItem!
    private var locationHint: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty { NSApp.terminate(nil); return }
        NSApp.setActivationPolicy(.accessory)
        let autosaveName = "ChatGPTConnection"
        let positionKey = "NSStatusItem Preferred Position " + autosaveName
        // Seed only our own item's initial order; Command-drag changes remain persistent.
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(0, forKey: positionKey)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = autosaveName
        statusItem.isVisible = true
        let menu = makeMenu()
        menu.delegate = self
        statusItem.menu = menu
        monitor.onChange = { [weak self] in self?.updateStatus() }
        monitor.start()
        updateStatus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            if !UserDefaults.standard.bool(forKey: "shownLocationHintV12") {
                self.showLocationHint()
                UserDefaults.standard.set(true, forKey: "shownLocationHintV12")
            }
        }
        if CommandLine.arguments.contains("--ui-diagnostics") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                self.statusItem.menu?.update()
                print("status item visible: \(self.statusItem.isVisible)")
                print("status frame: \(String(describing: self.statusItem.button?.window?.frame))")
                print("status window visible: \(String(describing: self.statusItem.button?.window?.isVisible))")
                print("menu entries: \(self.statusItem.menu?.items.count ?? 0)")
                for screen in NSScreen.screens {
                    print("screen: \(screen.frame); safe insets: \(screen.safeAreaInsets); left: \(String(describing: screen.auxiliaryTopLeftArea)); right: \(String(describing: screen.auxiliaryTopRightArea))")
                }
                fflush(stdout)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLocationHint()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        locationHint?.close()
        monitor.stop()
    }

    func showLocationHint() {
        guard let button = statusItem?.button else { return }
        if locationHint == nil {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentViewController = NSHostingController(rootView: LocationHintView(monitor: monitor))
            locationHint = popover
        }
        locationHint?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func updateStatus() {
        guard let button = statusItem?.button else { return }
        // A small unframed connection indicator, aligned with native menu-bar symbols.
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { [state = monitor.result.state] _ in
            let color = NSColor(state.color)
            let ring = NSBezierPath(ovalIn: NSRect(x: 2.5, y: 2.5, width: 11, height: 11))
            color.withAlphaComponent(0.72).setStroke()
            ring.lineWidth = 1.25
            ring.stroke()
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 5.5, y: 5.5, width: 5, height: 5)).fill()
            return true
        }
        image.isTemplate = false
        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""
        button.setAccessibilityLabel("ChatGPT 网络灯，" + monitor.result.title)
        button.toolTip = "\(monitor.result.title)\n\(monitor.result.detail)\n点击查看详情或立即检测"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let fresh = makeMenu()
        menu.removeAllItems()
        for item in fresh.items {
            fresh.removeItem(item)
            menu.addItem(item)
        }
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func info(_ title: String) { let item = NSMenuItem(title: title, action: nil, keyEquivalent: ""); item.isEnabled = false; menu.addItem(item) }
        func action(_ title: String, _ selector: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            return item
        }
        info(monitor.result.title)
        info(monitor.result.detail)
        if monitor.result.state != .checking {
            let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"
            info("最近检测：\(formatter.string(from: monitor.result.checkedAt))")
            if let code = monitor.result.httpStatus { info("官网响应：HTTP \(code)") }
        }
        menu.addItem(.separator())
        _ = action("立即检测", #selector(recheck))
        _ = action("打开 ChatGPT 官网", #selector(openWebsite))
        menu.addItem(.separator())
        let intervalItem = NSMenuItem(title: "常规检测间隔", action: nil, keyEquivalent: "")
        let intervals = NSMenu()
        for seconds in [5, 15, 30] {
            let item = NSMenuItem(title: "\(seconds) 秒", action: #selector(changeInterval(_:)), keyEquivalent: "")
            item.tag = seconds; item.target = self
            item.state = monitor.interval == Double(seconds) ? .on : .off
            intervals.addItem(item)
        }
        intervalItem.submenu = intervals; menu.addItem(intervalItem)
        menu.addItem(.separator())
        _ = action("检测原理与说明", #selector(showAbout))
        _ = action("退出网络灯", #selector(quit))
        return menu
    }

    @objc func recheck() { monitor.check() }
    @objc func openWebsite() { NSWorkspace.shared.open(URL(string: "https://chatgpt.com/")!) }
    @objc func changeInterval(_ item: NSMenuItem) { monitor.setInterval(Double(item.tag)) }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "ChatGPT 网络灯"
        alert.informativeText = "绿灯：ChatGPT 官网正常返回页面。\n红灯：连接失败、超时或官网服务异常。\n黄灯：官网有响应，但被验证 / 拦截，或页面无法确认。\n灰灯：正在检测。\n\n使用 macOS 系统网络和代理，每次建立新检测会话。网络切换后约 30 秒内加快重试，常规每 \(Int(monitor.interval)) 秒检测一次。单次检测最多等待约 8 秒。\n\n无需 API 密钥，不读取浏览器 Cookie 或聊天内容，不修改 VPN。官网可达可作为桌面端的连接参考；不检查登录、发消息、流式连接或应用专属代理。\n\n右上角菜单栏的小圆灯显示网络状态；点击查看详情或立即检测。按住 Command 可拖动图标调整顺序。"
        alert.addButton(withTitle: "知道了")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
