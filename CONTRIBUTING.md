# Contributing to StudyQuest

Thanks for your interest in StudyQuest! Bug reports, ideas, and pull requests are welcome.

## Reporting issues

Before opening an issue, search existing ones to avoid duplicates. For bugs, include:

- What happened and what you expected;
- Steps to reproduce;
- macOS version and Swift version (`swift --version`).

Never paste API keys, tokens, or personal study data into an issue.

## Development setup

You need macOS 14 or later and Swift 6. Command Line Tools are enough; Xcode is not required.

```bash
swift build
swift test
```

To package the app bundle, run `./scripts/bundle-app.sh`.

## Pull requests

1. Fork the repository and create a branch from `main`.
2. Keep each pull request focused on one change.
3. Add or update tests for behavior changes, and make sure `swift test` passes.
4. Follow the existing code style; avoid unrelated reformatting or renames.
5. Add an entry under `Unreleased` in [CHANGELOG.md](CHANGELOG.md) for user-visible changes.
6. Describe what changed and how you verified it in the pull request.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): summary`.

- `type`: `feat`, `fix`, `refactor`, `perf`, `docs`, `test`, `style`, or `chore`.
- `scope`: the area affected, such as `core`, `mcp`, or `app`.

Example: `fix(core): count daily new-card limit per day`.

## License

StudyQuest is licensed under [GPL-3.0](LICENSE). By contributing, you agree that your contributions are licensed under the same terms.
