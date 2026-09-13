# MiniStats

轻量原生 macOS 菜单栏资源监控器，使用 SwiftUI，无第三方依赖。

## 当前功能

- 菜单栏将上传、下载速率上下分组显示，右侧独立显示 CPU 占用，每秒采样；固定宽度和等宽数字减少刷新跳动。
- 网络数值紧邻箭头，按 KB/s、MB/s、GB/s 自动换算；小于 10 时最多保留一位小数，其余显示整数，四舍五入到 1000 前切换单位。超出显示范围时显示 `999+ GB/s`。
- 点击菜单栏打开详情，查看 CPU、内存和物理网卡流量。
- 不显示 Dock 图标，可从详情面板退出。
- 提供命令行采样模式，便于验证真实系统指标。

## 开发和启动

需要 macOS 13 或更新版本，以及 Swift 5.9+ 开发工具链（Xcode 或 Command Line Tools）。

```bash
bash scripts/run.sh
```

构建产物位于 `dist/MiniStats.app`，可双击启动。仅构建：

```bash
bash scripts/build.sh
```

测试及真实采样：

```bash
swift test --disable-sandbox
dist/MiniStats.app/Contents/MacOS/MiniStats --sample
```

可以在 Xcode 中打开 `Package.swift` 编辑项目。构建脚本生成本地临时签名应用；尚未配置 Developer ID 签名或公证。

## 指标口径

- CPU：系统累计 CPU tick 的相邻采样差值，所有核心整体归一化为 0–100%。
- 网络：汇总处于启用状态的 `en*` 网卡（通常为 Wi-Fi/以太网）；排除回环、VPN 和桥接接口，避免重复计算。非 `en*` 接口暂不支持。KB/MB 使用十进制单位，显示的是字节速率而非比特速率。
- 内存：用匿名页、有线页和压缩器实际占用页减去可清除页来估算已用物理内存，与活动监视器可能存在口径差异；不表示内存压力。
- 首次采样或休眠后首个长间隔显示 `—`，下一次有效采样恢复。网卡新增、消失或计数器重置不会产生巨大速率尖峰。

## 结构

- `Sources/MiniStats/Metrics.swift`：系统采集、差值计算和格式化。
- `Sources/MiniStats/Monitor.swift`：采样状态和定时更新。
- `Sources/MiniStats/MiniStatsApp.swift`：菜单栏与详情面板。
- `Tests/MiniStatsTests`：CPU 与网络差值边界测试。

暂未实现开机启动、历史图表、自定义显示项、温度与风扇监控。
