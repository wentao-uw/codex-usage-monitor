<p align="center">
  <img src="docs/assets/app-icon.png" width="132" alt="Codex Usage Monitor 应用图标">
</p>

<h1 align="center">Codex Usage Monitor</h1>

<p align="center">
  <a href="README.md">English</a> · <strong>简体中文</strong>
</p>

<p align="center">
  一款常驻 macOS 菜单栏的本地 Codex 用量工具，一次点击即可查看 Token、当前周期、模型分布、缓存效率和 API 等价费用。
</p>

<p align="center">
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-111827?logo=apple&logoColor=white">
  <img alt="Swift 5.9" src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white">
  <img alt="Node.js 18+" src="https://img.shields.io/badge/Node.js-18%2B-339933?logo=nodedotjs&logoColor=white">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-2563EB"></a>
  <img alt="数据仅保存在本地" src="https://img.shields.io/badge/数据-仅本地处理-14B8A6">
</p>

![Codex Usage Monitor macOS 界面，图中为虚构演示数据](docs/assets/menu-bar-preview.png)

> 截图使用虚构数据。应用只读取本机 Codex 日志，不会上传你的用量、会话内容或账户信息。

## 它解决什么问题？

Codex 可以展示当前任务的信息，但当你想知道“这个 7 天周期一共用了多少”“主要用量来自哪个模型”“缓存究竟节省了多少成本”时，通常需要翻日志或打开其他页面。

Codex Usage Monitor 把这些数据整理成一个常驻菜单栏的小窗口：需要时点开，看完即走，不打断工作。

## 核心功能

| 功能 | 说明 |
| --- | --- |
| **历史累计** | 汇总这台 Mac 上找到的全部本地会话 Token 和 API 等价费用。 |
| **当前周期** | 统计最长有效滚动窗口开始后的用量，通常对应 7 天周期。 |
| **完整 Token 构成** | 分别显示输入、缓存输入、输出、推理 Token、缓存命中率和当前上下文占用。 |
| **按模型统计** | 在当前周期与历史累计之间切换，查看每个模型的 Token 构成及费用估算。 |
| **滚动限制** | 显示本地日志里记录的使用比例和重置时间。 |
| **中英文切换** | 界面可以随时切换中文或英文。 |
| **灵活刷新** | 可手动刷新，也可选择关闭自动刷新，或设置为 1、5、10、15、30、60 分钟。 |
| **增量扫描** | 首次读取历史记录后，只处理发生变化的会话和新增日志内容。 |
| **用量提醒** | 可选择在滚动限制达到 50%、75% 或 90% 时通知；每个周期只提醒一次。 |
| **更原生的 Mac 体验** | 支持应用内设置登录时启动、唤醒后刷新，以及安全的虚构数据演示模式。 |

## macOS 快速开始

可以从 [GitHub Releases](https://github.com/wentao-uw/codex-usage-monitor/releases/latest) 下载最新开源构建，或者在 macOS 13 或更高版本上用 Xcode Command Line Tools 自行构建：

```bash
git clone https://github.com/wentao-uw/codex-usage-monitor.git
cd codex-usage-monitor
npm run build:macos
open "dist/Codex Usage Monitor.app"
```

启动后点击 macOS 菜单栏中的统计图标即可查看用量。

### 设置自动刷新时间

在窗口底部打开自动刷新菜单，可选择：

- 关闭
- 1 分钟
- 5 分钟
- 10 分钟（默认）
- 15 分钟
- 30 分钟
- 1 小时

设置会自动保存，下次启动仍然生效。无论是否开启自动刷新，都可以随时点击“手动刷新”。长时间后再次打开菜单，或 Mac 从睡眠中唤醒时，也会刷新过期数据。

窗口底部的 **设置** 菜单还可以开启登录时启动、设置滚动限制通知、切换虚构数据演示模式，以及手动检查 GitHub 新版本。只有点击检查命令时才会联网。

Release 中的应用使用 ad-hoc 签名，以便保持开源构建透明；不包含 Developer ID 签名或公证步骤。根据 Gatekeeper 设置，首次打开时可能需要按住 Control 点击应用并选择“打开”。

## 指标说明

- **历史累计**：汇总 `~/.codex/sessions` 和 `~/.codex/archived_sessions` 中每个会话最后记录的累计用量。
- **当前周期**：从本地日志中最长滚动限制周期的起点开始统计；同时存在 5 小时和 7 天限制时，周期统计使用 7 天窗口。
- **API 等价费用**：按照对应模型的 API 公开价格估算，不代表你的 Codex 订阅账单或实际扣费。
- **缓存输入**：会计入 Token 总量，但在费用计算时使用缓存输入价格。
- **`≥` 费用**：表示至少有一个模型没有匹配到价格，界面展示的是已知模型的最低费用，而不是把未知模型当成免费。

由于这里只读取本机日志，在其他电脑、云端任务或未保存在本机的环境中产生的用量不会被统计。

## 隐私设计

- 所有统计都在本机完成。
- 不进行后台网络请求，也不会发送日志、Token 或账户数据。
- 仅当你主动选择“检查更新”时访问 GitHub 的公开 Releases API。
- 不包含遥测或分析 SDK。
- 不需要 OpenAI API Key。
- 刷新偏好和通知去重标记保存在 macOS 本地用户设置中；解析后的会话数据仅保存在当前应用进程中。

核心读取逻辑可以在 [`UsageScanner.swift`](macos/CodexUsageMenuBar/Sources/UsageCore/UsageScanner.swift) 和 [`session.js`](lib/session.js) 中直接审查。

## 在 Codex 和终端中使用

这个仓库同时也是一个零运行时依赖的 Codex 插件：

```bash
git clone https://github.com/wentao-uw/codex-usage-monitor.git \
  ~/.codex/plugins/codex-usage-monitor
```

重新打开一个 Codex 任务，然后说：

```text
显示我的 Codex 用量。
```

也可以直接从终端查看：

```bash
node ~/.codex/plugins/codex-usage-monitor/bin/codex-usage-monitor.js summary
node ~/.codex/plugins/codex-usage-monitor/bin/codex-usage-monitor.js statusline
node ~/.codex/plugins/codex-usage-monitor/bin/codex-usage-monitor.js watch --interval 60
```

插件附带的 `Stop` 和 `PostToolUse` hooks 只读取本地文件，不会消耗模型额度。

## 开发与验证

```bash
npm test
npm run test:macos
npm run build:macos
```

构建结果位于 `dist/Codex Usage Monitor.app`。带版本标签的提交会由 GitHub Actions 测试并打包，其中没有 Developer ID 或公证步骤。架构说明见 [`docs/DESIGN.md`](docs/DESIGN.md)，贡献指南见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

## License

[MIT](LICENSE)

这是一个独立的非官方项目，与 OpenAI 不存在隶属或背书关系。
