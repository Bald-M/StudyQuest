# StudyQuest

English | [简体中文](README.zh-CN.md)

> Work in progress. No usable release yet.

StudyQuest is a native macOS study app that turns a 10-stage, zero-to-job-ready learning roadmap into daily tasks:

- Spaced-repetition review for flashcards and missed questions;
- Assignments, weekly quizzes, and stage exams — pass the exam to unlock the next stage;
- XP, levels, and study streaks;
- Grading by an AI provider configured in the app (OpenAI-compatible or Anthropic API);
- A built-in MCP server (stdio) so AI assistants such as Claude Code can read and update progress and create questions.

## Requirements

- macOS 14 or later
- Swift 6 (Command Line Tools are enough; Xcode is not required)

## Build

```bash
swift build
swift test
./scripts/bundle-app.sh   # packages build/StudyQuest.app
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Changes are recorded in [CHANGELOG.md](CHANGELOG.md).

## License

[GPL-3.0](LICENSE)
