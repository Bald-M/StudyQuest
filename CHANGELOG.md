# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Blue-to-cyan StudyQuest app icon and standalone transparent logo mark.
- GPL-3.0 license.
- README in English and Simplified Chinese.
- Contributing guide and changelog.
- Native macOS app with a 10-stage roadmap, stage detail, and answering screens.
- Spaced-repetition review for flashcards and missed questions.
- Assignments, weekly quizzes, and stage exams with a pass line, cooldown, and stage unlock.
- XP, levels, study streaks, and a progress/growth page.
- Mock interviews.
- AI grading and generation through OpenAI-compatible or Anthropic providers, with API keys kept in the Keychain.
- Built-in MCP server (`studyquest-mcp`) for reading progress, creating cards, problems, assignments, and exams, and submitting grades.
- Database export and restore from Settings.
- One-click MCP connect for Claude Code, Codex, and DeepSeek Harness from Settings.
- Provider editor: pick the model from a dropdown filled from the provider's model list, or type it in.

### Changed

- Settings: the MCP section no longer shows the `studyquest-mcp` path or the per-client command hints.
