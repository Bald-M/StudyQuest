# StudyQuest

[English](README.md) | 简体中文

> 开发中，尚未发布可用版本。

StudyQuest 是一个原生 macOS 学习应用，把一条"从 0 到能就业"的 10 阶段学习路线变成每日任务：

- 按间隔重复排期记忆卡片和错题复习；
- 作业、周测、阶段考试，考过才解锁下一阶段；
- 经验值、等级、连续学习天数；
- 判卷由应用内配置的 AI 服务完成（OpenAI 兼容接口或 Anthropic 接口）；
- 内置 MCP 服务（stdio），让 Claude Code 等 AI 助手读写进度、出题录题。

## 环境

- macOS 14 及以上
- Swift 6（只需 Command Line Tools，不依赖 Xcode）

## 构建

```bash
swift build
swift test
./scripts/bundle-app.sh   # 打包成 build/StudyQuest.app
```

## 参与贡献

见 [CONTRIBUTING.md](CONTRIBUTING.md)（英文）。变更记录见 [CHANGELOG.md](CHANGELOG.md)。

## 许可证

[GPL-3.0](LICENSE)
