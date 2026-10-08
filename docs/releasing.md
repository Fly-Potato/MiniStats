# 发布与更新维护

## 更新链路

生产版使用 Sparkle 2.10.0，读取 `config/release.json` 中的 GitHub Releases 清单地址。安装包和清单均验证 EdDSA 签名；每次发布的 ZIP 使用带版本标签的固定下载地址。开发版不创建更新器。

默认由 Sparkle 首次询问是否允许自动检查，也可以在详情面板修改；检查间隔为 24 小时，下载和安装由用户确认。后台网络错误不打断工作，手动检查通过 Sparkle 窗口显示结果。当前没有 Developer ID 签名或公证，初次下载仍可能受到 macOS 安全检查影响；更新包签名不等于 Apple 公证。

## 密钥

私钥位于本机登录钥匙串，Sparkle 账户名为 `MiniStats-updates`；仓库只保存 `config/sparkle-public-key.txt`。先执行 `swift package resolve` 下载官方工具，首次初始化使用：

```bash
bash scripts/setup-update-key.sh
```

该脚本会检查已有公钥，不会覆盖不匹配的公钥。换机器应从安全备份恢复原私钥，不要生成新密钥覆盖发布身份。私钥丢失后可能需要用户重新手动安装，才能恢复更新。

如需备份，使用 Sparkle 的 `generate_keys --account MiniStats-updates -x <仓库外的安全路径>` 导出，并放入加密备份；导出的文件是私钥，不能进入 Git、Release 附件或日志。恢复时使用同工具的 `-f <备份路径>`，随后再次核对公钥。

## 准备发布

1. 修改 `config/release.json`：`version` 使用 `x.y.z`，`build` 为严格递增的正整数。
2. 在 `docs/releases/<版本>.md` 编写中文更新说明，并更新 README 中受影响的行为。
3. 执行测试和两种构建，完成界面检查。提交本次发布源码，工作区必须干净。
4. 在沙箱外执行准备命令（内部使用 `gh` 读取已有正式版本并保留历史清单）：

```bash
python3 scripts/release.py prepare --notes docs/releases/0.2.0.md
```

输出在 `dist/releases/0.2.0/`，包括应用 ZIP、签名清单和源码提交记录。脚本拒绝旧构建号和已有输出目录；失败后先检查输出，再将残留目录移走重试。不生成差量包。切勿修改已签名清单或覆盖已发布附件。

构建脚本默认生成当前机器架构的程序，上传前使用 `file dist/MiniStats.app/Contents/MacOS/MiniStats` 核对，并在更新说明中标注支持的架构。本次 0.2.0 安装包为 arm64。

## 上传与发布

仅在获授权后，在沙箱外创建草稿：

```bash
python3 scripts/release.py draft
```

脚本检查工作区和源码提交，再验证签名后上传，创建 Draft Release，不立即公开。核对包版本、更新说明和附件完整性后，单独发布并指定 Latest：

```bash
gh release edit v0.2.0 --repo Fly-Potato/MiniStats --draft=false --latest
```

仅正式版本可设为 Latest；发布新版本时将命令中的版本同步替换。首个公开版本发布前，正式更新 URL 尚不可用，不能把“已接入更新器”描述为“已上线更新服务”。

## 首次安装与验收

旧版本没有更新器，需要手动安装一次新版本。日常使用建议放在 `~/Applications` 或 `/Applications`，开发版继续使用项目内构建产物。更新重启后内存历史重新积累，用户设置保留。

本地隔离测试从已锁定版本的 Sparkle 源码构建官方命令行更新器（发布包不包含该 CLI）：

```bash
bash scripts/build-update-test-tool.sh
python3 scripts/test-update.py
```

以上含 `gh`、钥匙串及安装测试的命令应在沙箱外运行。测试只操作临时目录里的应用，使用每次独立的 `local.ministats.update-test.*` 标识，验证签名、篡改清单及安装包的拒绝、旧版保留和 1 → 2 安装；仅测试服务使用回环 HTTP，生产始终使用 HTTPS。真实 GitHub 下载、首次安装提示和更新对话框仍需单独验证。

2026-10-08 本地验证：12 项单元测试、Debug/Release 构建和真实采样通过；隔离升级完成，篡改清单与安装包均被签名校验拒绝，旧版保持构建号 1。图形界面自动化工具连接超时，尚未完成更新入口及对话框的视觉验收；上述测试不包含真实 GitHub 更新源验收。
