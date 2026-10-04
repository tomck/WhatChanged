# Claude Code instructions

Read `AGENTS.md`; it governs this repository.

## Commits

- Never run a bare `git commit`, and never add a `Co-Authored-By` trailer.
  Commit only with:
  `scripts/claude-commit.sh --model <exact model ID> --effort <level> -- <git commit args>`
- Use the exact model ID from the session (for example `claude-sonnet-5-5`).
  Pass `--effort` only with the level actually in use; omit it rather than
  guess. The Claude Code version is detected automatically.
- Do not commit, tag, push, or publish unless the user asks.
