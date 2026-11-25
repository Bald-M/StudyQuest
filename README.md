# StudyQuest

English | [简体中文](README.zh-CN.md)

> Early stage: the v1 features below are implemented, but there is no packaged release yet. Build it from source.

StudyQuest is a native macOS study app that turns a 10-stage, zero-to-job-ready learning roadmap into daily tasks:

- Spaced-repetition review for flashcards and missed questions;
- Assignments, weekly quizzes, and stage exams — pass the exam to unlock the next stage;
- XP, levels, and study streaks;
- Grading by an AI provider configured in the app (OpenAI-compatible or Anthropic API);
- A built-in MCP server (stdio) so AI assistants such as Claude Code can read and update progress and create questions.

## Requirements

- macOS 14 or later
- Swift 6.0 Command Line Tools (Xcode is optional)

## Build & run

```bash
swift test
./scripts/bundle-app.sh   # packages build/StudyQuest.app
open build/StudyQuest.app
```

Dependency versions are pinned (GRDB 7.8.0, MCP swift-sdk 0.10.1) because newer releases need Swift 6.1.

## Configure an AI provider

Open Settings → AI 服务商 and add a provider. API keys are stored in the macOS Keychain only, never in the database.

- OpenAI-compatible: any endpoint that serves `{base URL}/chat/completions`, e.g. DeepSeek with its base URL.
- Anthropic: the default model is `claude-opus-5-5`.

## Connect MCP

The MCP server binary is `StudyQuest.app/Contents/MacOS/studyquest-mcp` (stdio). Replace `<path>` with its absolute path.

Claude Code:

```bash
claude mcp add studyquest -- '<path>'
```

Codex, in `~/.codex/config.toml`:

```toml
[mcp_servers.studyquest]
command = "<path>"
```

The tools can read progress and stages, create cards, problems, assignments, and exams, and grade submitted attempts (`submit_grading`).

## Data & backup

The database is `~/Library/Application Support/StudyQuest/studyquest.sqlite`. Export a backup and restore from one in Settings; a restore keeps the previous database as `studyquest.sqlite.pre-restore`. Set `STUDYQUEST_DB_PATH` to use another database file, e.g. for testing.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Changes are recorded in [CHANGELOG.md](CHANGELOG.md).

## License

[GPL-3.0](LICENSE)
