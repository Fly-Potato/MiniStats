# Repository Guidelines

## 项目结构与模块职责

MiniStats 是原生 macOS 菜单栏资源监控工具，使用 Swift 5.9+、SwiftUI 和 Swift Package Manager，最低支持 macOS 13，无第三方依赖。

- `Sources/MiniStats/Metrics.swift`：系统指标采集、CPU 与网络差值计算、显示格式化。
- `Sources/MiniStats/Monitor.swift`：可观察状态与每秒采样生命周期。
- `Sources/MiniStats/MiniStatsApp.swift`：菜单栏标签和详情面板。
- `Sources/MiniStats/main.swift`：应用入口与 `--sample` 采样模式。
- `Tests/MiniStatsTests/`：XCTest 单元测试。
- `scripts/`：构建与启动脚本。目前没有独立资源目录；`.build/` 和 `dist/` 为已忽略的生成产物。

## 构建、测试与本地开发

安装 macOS Swift 开发工具链后，在仓库根目录执行：

```bash
bash scripts/build.sh      # Release 构建、组装应用并进行本地临时签名
bash scripts/run.sh        # 构建并启动菜单栏应用
swift test --disable-sandbox  # 运行 XCTest 测试
dist/MiniStats.app/Contents/MacOS/MiniStats --sample  # 构建后验证真实系统采样
```

应用产物为 `dist/MiniStats.app`。采样模式在必要指标不可用时返回非零退出码。可使用 Xcode 打开 `Package.swift`；目前未配置分发签名或公证。

## 代码风格与命名

使用四空格缩进；类型使用 `UpperCamelCase`，方法和属性使用 `lowerCamelCase`。遵循现有 Swift 排版，目前没有配置格式化或 lint 工具。

指标优先使用小型值类型，系统采集与 SwiftUI 视图保持分离，可观察 UI 状态在主线程更新。界面文案、README 和贡献说明使用中文。修改指标口径时同步更新文档。

## 测试要求

测试文件命名为 `*Tests.swift`，测试方法以 `test` 开头并描述预期行为，例如 `testCounterResetDoesNotProduceSpike`。目前没有数值化覆盖率门槛。

计算逻辑变更应补充针对性测试，关注采样间隔、计数器重置、网卡增减和缺失数据；不要断言实时 CPU 或网速的固定数值。运行逻辑变更需执行单元测试和 `--sample`；界面变更需手动检查菜单栏与详情面板。分别报告编译、采样和界面验证结果，不能以编译成功代替界面验证。

## 提交与合并请求

仓库尚无提交历史，因此没有既有提交信息规范。建议使用简短、明确的动作描述，例如“修复网络计数器重置处理”，每次提交聚焦一个变更，不包含生成产物。

合并请求应说明行为变化、验证方式和已知限制；存在关联问题时附上链接，界面变更附截图。涉及指标定义或支持的网络接口范围时，明确说明变化及其影响。
