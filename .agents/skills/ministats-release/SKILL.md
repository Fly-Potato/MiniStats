---
name: ministats-release
description: 为 MiniStats 准备版本与更新说明、验证源码、推送版本 tag 并跟踪自动发布结果。用于用户要求发版、打发布 tag 或排查发布失败；普通提交与 CI 修改不执行发版。
---

# MiniStats 发版

在仓库根目录操作。先读 [AGENTS.md](../../../AGENTS.md) 和 [发布维护说明](../../../docs/releasing.md)，复用 `scripts/release.py`、`scripts/verify-build.py` 与 Release 工作流，不另写发布链路。

## 准备版本

- 检查分支、工作区差异、远端 main 和已有版本，保留用户改动。按用户指定版本发版；未指定时，根据实际变化选择语义化版本并说明选择。
- 更新 `config/release.json` 的 `version` 和严格递增的 `build`，新增 `docs/releases/<版本>.md`，同步受影响的 README 内容。版本高于 Latest，tag 固定为 `vX.Y.Z`，不支持预发布后缀。
- 执行 Swift/Python 测试、Debug/Release 构建和 `scripts/verify-build.py`。菜单栏、更新入口及安装体验需要界面验收；如无法完成，如实报告限制。
- 只读检查 `release` 环境已允许 `v*` tag 且存在 `SPARKLE_PRIVATE_KEY` Secret。不读取、导出、打印或自行上传私钥；缺少配置时完成源码准备并说明配置步骤。

## 触发自动发布

推送版本 tag 会公开 GitHub Release 并切换 Latest。用户明确要求发布该版本时，这就是发布动作；仅“修改 CI”“准备发版”或“提交并推送”不授权推送发布 tag。

遵循已有提交与推送授权，将版本源码提交并推送到 main，确认普通 CI 成功、目标提交已进入远端 main、工作区干净，再创建带说明的 tag 并仅推送该 tag。以下以已确认的 `0.2.1` 为例，执行时替换为实际版本：

```bash
git tag -a v0.2.1 -m 'MiniStats 0.2.1'
python3 scripts/release.py validate-tag --tag v0.2.1
git push origin refs/tags/v0.2.1
```

所有 `gh` 调用必须在沙箱外执行。跟踪该 tag/提交对应的 Release run，确认正式 Release 的版本、目标提交、两个附件及 Latest，再检查公开清单和生产版“检查更新”。报告版本、提交、运行链接、Release 链接及实际验证结果。

## 失败处理

未创建 Release 时可在修复外部环境后重跑原 tag；源码有错则准备新版本。若已留下草稿或正式 Release，先检查远端状态和附件，停止自动重试并报告具体恢复方式。不得强推或移动发布 tag、覆盖正式附件、轮换签名公钥，也不能把“已触发”当作“已发布”。
