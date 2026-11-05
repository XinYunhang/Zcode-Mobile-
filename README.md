# ZCode Shell（iOS 薄壳）

把 ZCode 的远程网页装进一个原生壳里，解决 Safari 切后台整页重载的问题。

壳本身不实现任何 Agent 功能：它加载你从电脑上拿到的那个 `zcode.z.ai/remote/v4?...` 链接，负责
配对、回前台探测、进程被回收后自动恢复，其余全部交给网页。

## 结构

```
project.yml                 XcodeGen 配置（工程文件由它生成，不入库）
App/
  ZCodeApp.swift            入口，已配对→网页 / 未配对→配对页
  Core.swift                链接存取、会话状态、连通性探测
  PairingView.swift         粘贴链接 + 分类型报错
  WebModel.swift            WKWebView 封装、进程终止恢复、滚动位置保存
  WebScreen.swift           网页容器 + 断线覆盖层 + 长按菜单
.github/workflows/ios.yml   macOS runner 构建未签名 ipa
```

## 为什么不把链接写进代码

远程链接里的 `sid` 就是访问你电脑的凭证。仓库是公开的，所以链接只在运行时由你粘贴，
只存本机 `UserDefaults`，不参与构建。

改链接的后果：换了地址会触发新的配对流程，旧的网页数据和滚动记录不保留。

## 构建

推送到 `main`，或手动触发 workflow，产物在 Actions 的 `ZCodeShell-unsigned` artifact 里。

本地（有 Mac 时）：

```bash
brew install xcodegen
xcodegen generate
open ZCodeShell.xcodeproj
```

## 装机（手机端自签，无需 Mac、无需电脑）

1. 从 Actions 下载 `ZCodeShell-unsigned` artifact 并解压，得到 `ZCodeShell-unsigned.ipa`
2. 把 ipa 传到手机（文件 App / AirDrop / 任意方式）
3. 用 lcsign 打开该 ipa，选择你的证书签名后安装
4. 若签名时报 Bundle ID 冲突，在签名界面把 `com.zcode.shell` 改成你自己的唯一 ID

证书和私钥始终只在你的手机和签名工具里，不经过这个仓库，也不经过构建流程。

## 已知边界

- **后台 WebSocket 必断**。壳能保证的是页面不被丢弃、不白屏、回来自动探测并给可点的重试，
  但网页自己的重连逻辑决定了断线后多久恢复。
- **极端内存压力下 WebContent 进程仍会被回收**。此时壳会静默重载并尽力恢复滚动位置，
  这是 iOS 的硬限制，浏览器和原生壳都躲不掉。
- **服务端若校验 User-Agent**，WKWebView 的 UA 不含 `Safari/` 标记，可能被区别对待。
  真遇到再加 UA 覆盖，先不动。
