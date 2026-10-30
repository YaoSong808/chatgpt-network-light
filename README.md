# ChatGPT 网络灯

一个轻量的 macOS 菜单栏小工具。看一眼右上角的灯，就知道当前网络能不能连上 ChatGPT 官网。

为需要频繁切换 VPN、代理和服务器网络的中国用户设计。无需 API 密钥，下载后即可运行。

![实际使用：右上角菜单栏中的绿色圆环表示 ChatGPT 官网可达](docs/images/menubar-overview.png)

图中耳机图标和搜索图标之间的**绿色圆环**就是网络灯。这是实际运行截图。

## 为什么做这个

这个项目起源于自动驾驶研发中的一个日常麻烦：连接服务器时，需要打开服务器或内网 VPN；而访问 ChatGPT，往往又需要另一套 VPN 或网络代理。

对有这类需求的中国用户来说，两套网络环境来回切换，很容易打断工作：开了服务器 VPN，ChatGPT 连不上；退出服务器 VPN，又要等一会儿才能恢复。有时代理已经切好了，DNS、路由或连接状态还没跟上。于是只能反复刷新网页，或者给桌面端发一句话试试，确认“现在到底通没通”。

**网络灯把这件事变成一个可以直接看见的状态。** 切换完网络，继续手头的工作；等右上角亮绿灯，再回到 ChatGPT。

## 用起来是什么样

平时，它只占一个系统菜单栏图标的位置：细圆环加中心色点，没有文字和黑色底板，不挡窗口，也没有 Dock 图标。

![实际截图的局部放大：绿色网络状态灯](docs/images/menubar-detail.png)

上图是同一张实际截图的局部放大。点击圆环可查看检测结果、最近检测时间和 HTTP 状态，也可以立即重测、打开官网或调整检测间隔。

| 灯色 | 当前状态 | 含义 |
| --- | --- | --- |
| 🟢 绿色 | 官网可达 | 通过 HTTPS 收到正常的 ChatGPT 官网 HTML 页面 |
| 🔴 红色 | 连接或服务失败 | 超时、DNS / HTTPS 连接失败，或官网返回 5xx |
| 🟡 黄色 | 需要确认 | 遇到验证、访问拦截、限流、异常重定向或无法识别的页面 |
| ⚪ 灰色 | 正在检测 | 正在重新连接，不沿用上一轮的绿灯 |

## 下载安装

当前发布包适用于 **Apple Silicon Mac，macOS 13 或以上**。

1. 前往 [下载页面](https://github.com/YaoSong808/chatgpt-network-light/releases/latest)，下载 `ChatGPT-Network-Light-macOS-arm64.zip`。
2. 解压，将 `ChatGPT网络灯.app` 拖到「应用程序」文件夹，然后打开。
3. 在右上角菜单栏找到小圆环。首次打开会显示一次定位提示，点击其他位置即可收起。

发布包使用本地签名，尚未经过 Apple 公证。也可以按下方步骤，在自己的 Mac 上从源码构建。

按住 **Command** 拖动图标，可以调整菜单栏顺序；再次打开应用会显示图标位置提示。如需登录时启动，可在 macOS「系统设置 → 通用 → 登录项与扩展」中自行添加应用。

## 切换网络后会发生什么

- 自动监听网络、DNS 和系统代理配置变化，触发重新检测。
- 启动或网络变化后的约 30 秒内，每轮检测结束后约 3 秒重试一次。
- 平时默认每轮结束后等待 15 秒，也可在菜单中选择 5 秒或 30 秒。
- 单次请求最多等待约 8 秒；实际恢复显示时间取决于网络连接和请求耗时。
- 电脑睡眠时暂停检测，唤醒后重新检查。

检测目标是 `https://chatgpt.com/`。每次使用新的临时网络会话，检查官网域名、HTTPS、HTTP 状态、页面特征和常见验证页。

**绿灯代表官网可达，可作为桌面端连接状况的参考。** 账户登录、真实发消息、流式连接和应用专属代理规则仍可能影响桌面端。浏览器能打开而灯为黄色时，可以从菜单打开官网，确认是否遇到网站验证。

## 隐私与开销

只向 ChatGPT 官网发送无登录状态的 HTTPS 请求，无需 API 密钥，不产生模型调用或 API 费用。

不读取浏览器 Cookie、密钥和聊天内容，不修改 VPN、代理或系统 DNS。应用使用 macOS 的默认系统网络和代理配置；浏览器扩展代理、应用专属分流可能走不同路径。

每轮最多读取前 64 KiB 的 HTML，随后取消会话；不加载页面脚本、图片和其他资源，也不记录网络日志。本地保存检测间隔、菜单栏位置和首次使用提示状态。官网会像普通网页访问一样收到网络出口 IP 和请求信息。

## 从源码构建

需要安装 Xcode 及对应命令行开发工具。项目使用 Swift、AppKit、SwiftUI、Network 和 SystemConfiguration，没有第三方依赖。

```sh
git clone https://github.com/YaoSong808/chatgpt-network-light.git
cd chatgpt-network-light
./build.command
open build/ChatGPT网络灯.app
```

默认构建目标为 Apple Silicon / macOS 13。可以传入自定义构建目录：

```sh
./build.command /绝对路径/输出目录
```

运行状态判断测试：

```sh
./test.command
```

现有 19 项测试覆盖正常页面、验证页、403、429、5xx、401、门户网页、空响应、非 HTML、重定向、HTTP 降级、域名欺骗、DNS、超时和证书失败。

只检测一次并输出 JSON：

```sh
./build/ChatGPT网络灯.app/Contents/MacOS/ChatGPTNetworkLight --probe-once
```

退出码：`0` 为官网可达，`1` 为连接或服务失败，`2` 为需要确认。

## 项目结构

```text
Sources/
  App.swift                 菜单栏界面、网络变化监听与检测调度
  Probe.swift               官网请求与状态判断
  main.swift                程序入口
Tests/
  ClassifierTests.swift     状态判断测试
docs/images/                实际使用截图
build.command               构建应用
test.command                运行测试
```

欢迎通过 [问题反馈](https://github.com/YaoSong808/chatgpt-network-light/issues) 提交使用体验、误判案例和改进建议。
