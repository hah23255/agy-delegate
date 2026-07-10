---
name: agy-delegate
description: Use when the user wants coding/implementation work delegated to Google Antigravity CLI (agy) agents instead of implemented directly — when they say "delegate to agy", "agy delegate", "hand this to antigravity", "fan this out to agy", or when kimi-delegate is unavailable/quota-exhausted and parallel local-agent delegation is still wanted.
---

# Agy Delegate

Turn Claude into a **manager** of Google Antigravity CLI (`agy`) agents. Claude does
the judgment work — decomposition, briefs, review. agy does the implementation volume.
Same doctrine as kimi-delegate; the executor and its contract differ.

## The contract you depend on (verified on agy v1.1.1, 2026-07-10)

agy runs inside the `debian` proot-distro container. The Termux wrapper
`~/.local/bin/agy` handles that transparently for any path under $HOME.

    agy --print --dangerously-skip-permissions --print-timeout 15m \
        [--model "Gemini 3.1 Pro (High)"] -p "FULL BRIEF"

- `--print` = non-interactive; result on stdout; exit code meaningful.
- Verified non-TTY safe via the proot path (GitHub issues #76/#318 do NOT
  reproduce here). agy SELF-UPDATES silently — if behavior shifts, run
  `scripts/agy_parallel.sh --verify` (3 contract checks, costs credits).
- `--dangerously-skip-permissions` = auto-approve: **trusted repos only**,
  prefer worktree isolation (the script's default).
- Model names contain spaces — always quote. `agy models` lists them.
  Route bulk work to "Gemini 3.5 Flash (High)" (default), hard briefs to
  "Gemini 3.1 Pro (High)" or "Claude Opus 4.6 (Thinking)" via brief frontmatter.
- No JSON output mode exists; structure is enforced by the schema gate below.
- Requires Google Pro/Ultra subscription; runs burn credits. On
  FAILED(quota): fall back to kimi-delegate, then native subagents.

## Workflow

1. **Scope & decompose** (Claude): disjoint file ownership per agent; 2–4 agents.
2. **Write briefs**: copy `assets/brief-template.md`; every section is required
   (the script lints). Optional frontmatter per brief:
   `model:`, `timeout:`, `schema:` (path to JSON schema for the output gate).
3. **Launch**:
       bash scripts/agy_parallel.sh --repo /path/to/repo briefs/*.md
   Worktree per brief on branch `agy/<name>`; logs in `.agy-runs/<ts>/`;
   `--max-parallel 3` default; exit = #failed agents.
4. **Schema gate** (when a brief declares `schema:`): the agent is instructed
   to end with one JSON object; `validate_output.py` checks it.
   Default `salvage` mode: valid fields land in `<name>.partial.json` with
   `_missing`/`_invalid` reports — status `PARTIAL(schema)` keeps the work
   reviewable instead of discarding it. `--schema-mode strict|warn` to change.
5. **Review & integrate** (Claude): read logs + `git -C <repo> diff base..agy/<name>`,
   run tests yourself, merge, report. Never trust agent self-reports.

## Statuses

OK · PARTIAL(schema) · FAILED(exit|timeout|quota|schema|schema-file|empty-brief|bad-timeout|worktree) — the
process exit code counts every FAILED item (agent failures and pre-launch
failures alike); PARTIAL never fails the run.
