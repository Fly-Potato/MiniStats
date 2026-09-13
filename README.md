# MiniStats

轻量原生 macOS 菜单栏资源监控器，使用 SwiftUI，无第三方依赖。

## 当前功能

- 菜单栏将上传、下载速率上下分组显示，右侧独立显示 CPU 占用，每秒采样；固定宽度和等宽数字减少刷新跳动。
- 网络数值紧邻箭头，按 KB/s、MB/s、GB/s 自动换算；小于 10 时最多保留一位小数，其余显示整数，四舍五入到 1000 前切换单位。超出显示范围时显示 `999+ GB/s`。
- 点击菜单栏打开详情，查看 CPU、内存和物理网卡流量。
- 详情面板包含 CPU、内存和网络折线图；网络用实线、虚线区分下载和上传。默认展示近 10 分钟，可统一切换到 30 或 60 分钟，并记住选择。
- 悬停图表可查看对应时间与数值；实时数值每秒更新，图表在面板显示时每两秒更新。
- 不显示 Dock 图标，可从详情面板退出。
- 提供命令行采样模式，便于验证真实系统指标。

## 开发和启动

需要 macOS 13 或更新版本，以及 Swift 5.9+ 开发工具链（Xcode 或 Command Line Tools）。

以下命令均在仓库根目录执行。开发运行（默认 Debug，菜单栏和详情标题显示 `DEV`）：

```bash
bash scripts/run.sh
```

日常使用的生产运行（Release，不显示 `DEV`）：

```bash
bash scripts/run.sh release
```

开发版产物为 `dist/MiniStats Dev.app`，生产版为 `dist/MiniStats.app`，均可双击启动。两者应用标识分别为 `local.ministats.app.dev` 和 `local.ministats.app`，可同时运行，设置与内存中的历史记录相互独立。标记由编译配置决定，不能在界面中切换。

仅构建：`bash scripts/build.sh debug` 构建开发版，`bash scripts/build.sh` 默认构建生产版。直接通过 SwiftPM 或 Xcode 使用 Debug 配置运行时也会显示开发标记；需要两版并行时建议使用上述打包脚本。

测试及真实采样（采样命令需要先完成构建）：

```bash
swift test --disable-sandbox
dist/MiniStats.app/Contents/MacOS/MiniStats --sample
```

可以在 Xcode 中打开 `Package.swift` 编辑项目。构建脚本生成本地临时签名应用；尚未配置 Developer ID 签名或公证。

`--sample` 输出一次真实系统采样，必要指标不可用时返回非零退出码；该模式不启动菜单栏界面。

## 指标口径

- CPU：系统累计 CPU tick 的相邻采样差值，所有核心整体归一化为 0–100%。
- 网络：汇总处于启用状态的 `en*` 网卡（通常为 Wi-Fi/以太网）；排除回环、VPN 和桥接接口，避免重复计算。非 `en*` 接口暂不支持。KB/MB/GB 使用十进制单位，显示的是字节速率而非比特速率。
- 内存：用匿名页、有线页和压缩器实际占用页减去可清除页来估算已用物理内存，与活动监视器可能存在口径差异；不表示内存压力。
- 首次采样或休眠后首个长间隔，CPU 和网速显示 `—`，下一次有效采样恢复；内存独立采集。网卡新增、消失或计数器重置不会产生巨大速率尖峰。

## 历史图表

应用运行时持续在内存中保留最近 60 分钟的采样，关闭详情面板不影响记录；退出或重启后重新积累，不保存到磁盘。数据不足时保留完整时间轴，未记录部分留空。休眠或采集失败造成的缺口不会补零或跨越连线；系统时间向后调整时重新开始记录。

CPU 和内存纵轴固定为 0–100%。网络两条线共用从零开始的纵轴，单位统一为 KB/s、MB/s 或 GB/s；峰值增大时立即扩展范围，持续低负载 30 秒后才缩小，减少跳动。长时间窗口通过保留每个时间桶的首尾与峰谷减少绘制点数，悬停数值仍来自原始采样。

## 项目结构

- `Package.swift`：平台要求、可执行目标和测试目标。
- `Sources/MiniStats/Metrics.swift`：系统采集、差值计算和格式化。
- `Sources/MiniStats/Monitor.swift`：采样状态和定时更新。
- `Sources/MiniStats/MiniStatsApp.swift`：应用场景与菜单栏标签。
- `Sources/MiniStats/BuildIdentity.swift`：按编译配置区分开发版和生产版。
- `Sources/MiniStats/Dashboard.swift`：详情图表、时间范围切换与悬停交互。
- `Sources/MiniStats/History.swift`：历史缓存、时间窗口裁剪、峰谷保留与网络纵轴缩放。
- `Sources/MiniStats/main.swift`：应用入口与命令行采样模式。
- `Tests/MiniStatsTests/`：指标计算、速率格式化、历史窗口与图表数据处理测试。
- `scripts/`：构建、打包与启动脚本。
- `.build/`、`dist/`：已被 Git 忽略的构建产物；目前没有独立资源目录。

## 当前限制

暂未实现开机启动、历史数据持久化、自定义显示项、温度与风扇监控。

## 参与贡献

修改代码前请阅读 [AGENTS.md](AGENTS.md)，其中规定了代码风格、验证要求、提交信息格式和合并请求要求。
