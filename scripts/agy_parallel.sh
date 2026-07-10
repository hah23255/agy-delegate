#!/data/data/com.termux/files/usr/bin/bash
# agy_parallel.sh — fan task briefs out to parallel Antigravity CLI (agy) agents.
#
# Usage:
#   agy_parallel.sh --repo <path> [options] BRIEF_FILE [BRIEF_FILE ...]
#
# Options:
#   --repo <path>          Target git repository (default: current directory)
#   --model <name>         Default agy model, e.g. "Gemini 3.5 Flash (High)" (quote it)
#   --timeout <dur>        Per-agent --print-timeout, Go duration (default 15m)
#   --no-worktree          Run all agents directly in --repo (disjoint scopes only)
#   --results-dir <path>   Where to write logs (default: <repo>/.agy-runs/<timestamp>)
#   --max-parallel <n>     Cap concurrent agents (default 3)
#   --base <ref>           Branch/ref to base worktrees on (default: current HEAD)
#   --schema-mode <m>      strict|salvage|warn (default salvage)
#   --no-lint              Skip brief section lint
#   --verify               Run the real-agy contract checks and exit (costs credits)
#   -h, --help             Show this help
#
# Brief frontmatter (optional YAML, overrides flags per brief):
#   ---
#   model: Gemini 3.1 Pro (High)
#   timeout: 20m
#   schema: relative/or/absolute/path.json
#   ---
#
# Exit status: 0 if all agents OK, otherwise the number of failed agents.
set -uo pipefail

AGY_BIN="${AGY_BIN:-agy}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/agy_lib.sh"
REPO="$(pwd)"
MODEL=""
TIMEOUT="15m"
USE_WORKTREE=1
RESULTS_DIR=""
MAX_PARALLEL=3
BASE_REF=""
SCHEMA_MODE="salvage"
LINT=1
VERIFY=0
BRIEFS=()

die() {
	echo "error: $*" >&2
	exit 1
}
show_help() {
	sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
	exit 0
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--repo)
		REPO="${2:?}"
		shift 2
		;;
	--model)
		MODEL="${2:?}"
		shift 2
		;;
	--timeout)
		TIMEOUT="${2:?}"
		shift 2
		;;
	--no-worktree)
		USE_WORKTREE=0
		shift
		;;
	--results-dir)
		RESULTS_DIR="${2:?}"
		shift 2
		;;
	--max-parallel)
		MAX_PARALLEL="${2:?}"
		shift 2
		;;
	--base)
		BASE_REF="${2:?}"
		shift 2
		;;
	--schema-mode)
		SCHEMA_MODE="${2:?}"
		shift 2
		;;
	--no-lint)
		LINT=0
		shift
		;;
	--verify)
		VERIFY=1
		shift
		;;
	-h | --help) show_help ;;
	-*) die "unknown option: $1" ;;
	*)
		BRIEFS+=("$1")
		shift
		;;
	esac
done

case "$SCHEMA_MODE" in strict | salvage | warn) ;; *) die "bad --schema-mode: $SCHEMA_MODE" ;; esac

# --verify handled in a later task; placeholder keeps flag parse honest.
if [[ $VERIFY -eq 1 ]]; then die "--verify not implemented yet"; fi

[[ ${#BRIEFS[@]} -gt 0 ]] || die "no brief files given. See --help."
[[ -d "$REPO" ]] || die "repo path not found: $REPO"
REPO="$(cd "$REPO" && pwd)"
for b in "${BRIEFS[@]}"; do
	[[ -f "$b" ]] || die "brief file not found: $b"
done

if [[ $LINT -eq 1 ]]; then
	for b in "${BRIEFS[@]}"; do
		lint_brief "$b" || exit 1
	done
fi

# TEMPORARY minimal launch (replaced in the launch-engine task)
for b in "${BRIEFS[@]}"; do
	"$AGY_BIN" --print --dangerously-skip-permissions -p "$(brief_body "$b")" >/dev/null 2>&1 || exit 1
done
exit 0
