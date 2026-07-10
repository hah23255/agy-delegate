# agy-delegate

Claude Code skill: delegate implementation briefs to parallel Google Antigravity
CLI (`agy`) agents with git-worktree isolation and a JSON-schema output gate.

- Spec: docs/superpowers/specs/2026-07-10-agy-delegate-design.md (in the home repo)
- Install: `bash install.sh` (symlinks this repo into `~/.claude/skills/`)
- Test:    `bash tests/test_install.sh && bash tests/test_agy_parallel.sh && python3 -m pytest tests/ -q`
  (all tests run against a stub — no credits used)
- Verify the real agy contract (costs credits): `bash scripts/agy_parallel.sh --verify`

Version: see VERSION. Deploy to another system: clone under $HOME, run install.sh
(requires agy installed in a proot-distro debian container + the Termux wrapper).
