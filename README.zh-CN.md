# StudyQuest

[English](README.md) | 简体中文

> 早期阶段：下列 v1 功能已实现，但尚无打包发布版本，请从源码构建。

StudyQuest 是一个原生 macOS 学习应用，把一条"从 0 到能就业"的 10 阶段学习路线变成每日任务：

- 按间隔重复排期记忆卡片和错题复习；
- 作业、周测、阶段考试，考过才解锁下一阶段；
- 经验值、等级、连续学习天数；
- 判卷由应用内配置的 AI 服务完成（OpenAI 兼容接口或 Anthropic 接口）；
- 内置 MCP 服务（stdio），让 Claude Code 等 AI 助手读写进度、出题录题。

## 环境

- macOS 14 及以上
- Swift 6.0 Command Line Tools（Xcode 可选）

## 构建与运行

```bash
swift test
./scripts/bundle-app.sh   # 打包成 build/StudyQuest.app
open build/StudyQuest.app
```

依赖版本已锁定（GRDB 7.8.0、MCP swift-sdk 0.10.1），因为更高版本需要 Swift 6.1。

## 配置 AI 服务商

打开「设置 → AI 服务商」添加服务商。API Key 只保存在 macOS 钥匙串，不写入数据库。

- OpenAI 兼容：任何提供 `{base URL}/chat/completions` 的接口，例如填入 DeepSeek 的 base URL。
- Anthropic：默认模型为 `claude-opus-5-5`。

## 接入 MCP

MCP 服务程序位于 `StudyQuest.app/Contents/MacOS/studyquest-mcp`（stdio）。下面的 `<path>` 换成它的绝对路径。

Claude Code：

```bash
claude mcp add studyquest -- '<path>'
```

Codex，写入 `~/.codex/config.toml`：

```toml
[mcp_servers.studyquest]
command = "<path>"
```

工具可读取进度与阶段，创建卡片、题目、作业和考试，并为已交卷的作答判卷（`submit_grading`）。

## 数据与备份

数据库位于 `~/Library/Application Support/StudyQuest/studyquest.sqlite`。可在设置中导出备份、从备份恢复；恢复时旧库保留为 `studyquest.sqlite.pre-restore`。恢复前请先退出正在使用 StudyQuest MCP 的 AI 助手。设置环境变量 `STUDYQUEST_DB_PATH` 可改用其他数据库文件，例如测试时。

## 参与贡献

见 [CONTRIBUTING.md](CONTRIBUTING.md)（英文）。变更记录见 [CHANGELOG.md](CHANGELOG.md)。

## 许可证

[GPL-3.0](LICENSE)
