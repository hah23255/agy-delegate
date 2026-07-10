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
	awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
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

if [[ $VERIFY -eq 1 ]]; then
	echo "agy contract check (COSTS CREDITS — real agent runs)"
	vfailed=0
	vtmp="$(mktemp -d)"
	trap 'rm -rf "$vtmp"' EXIT

	# 1. version
	if v="$("$AGY_BIN" --version 2>/dev/null)"; then
		echo "  PASS  version: $v"
	else
		echo "  FAIL  version: agy not reachable"
		vfailed=$((vfailed + 1))
	fi

	# 2. non-TTY echo
	r="$("$AGY_BIN" -p 'Reply with exactly the word OK and nothing else' --print-timeout 90s 2>/dev/null)"
	if [[ "$r" == *OK* ]]; then
		echo "  PASS  non-TTY echo"
	else
		echo "  FAIL  non-TTY echo (got: ${r:0:60})"
		vfailed=$((vfailed + 1))
	fi

	# 3. file edit with auto-approve
	printf 'color: RED\n' >"$vtmp/test.txt"
	(
		cd "$vtmp" && "$AGY_BIN" -p 'Edit the file test.txt in the current directory: replace the word RED with GREEN. Then stop.' \
			--dangerously-skip-permissions --print-timeout 240s
	) >/dev/null 2>&1
	if awk '/GREEN/{found=1} END{exit !found}' "$vtmp/test.txt"; then
		echo "  PASS  file edit"
	else
		echo "  FAIL  file edit"
		vfailed=$((vfailed + 1))
	fi

	echo "verify: $((3 - vfailed))/3 checks passed"
	exit $vfailed
fi

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

dup="$(for b in "${BRIEFS[@]}"; do
	n="$(basename "${b%.*}")"
	sanitize_name "$n"
	echo
done | sort | uniq -d | head -n 1)"
[[ -z "$dup" ]] || die "duplicate brief name after sanitization: $dup (rename one brief)"

IS_GIT=0
if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then IS_GIT=1; fi
if [[ $USE_WORKTREE -eq 1 && $IS_GIT -eq 0 ]]; then
	echo "note: $REPO is not a git repo — falling back to --no-worktree." >&2
	USE_WORKTREE=0
fi
if [[ -z "$BASE_REF" && $IS_GIT -eq 1 ]]; then
	BASE_REF="$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"
fi

TS="$(date +%Y%m%d-%H%M%S)"
[[ -n "$RESULTS_DIR" ]] || RESULTS_DIR="$REPO/.agy-runs/$TS"
mkdir -p "$RESULTS_DIR"

{
	echo "agy version: $("$AGY_BIN" --version 2>/dev/null || echo unknown)"
	echo "started: $(date)"
	echo "schema-mode: $SCHEMA_MODE"
} >"$RESULTS_DIR/meta.txt"

echo "agy parallel delegation"
echo "  repo:        $REPO"
echo "  briefs:      ${#BRIEFS[@]}"
echo "  isolation:   $([[ $USE_WORKTREE -eq 1 ]] && echo "git worktree (base: $BASE_REF)" || echo "none (in-place)")"
echo "  results dir: $RESULTS_DIR"
echo

declare -a NAMES PIDS WORKDIRS BRANCHES SCHEMAS
run_count=0
failed_prelaunch=0

run_one() {
	local brief="$1" name workdir branch logfile bmodel btimeout bschema secs badt
	name="$(sanitize_name "$(basename "${brief%.*}")")"
	logfile="$RESULTS_DIR/$name.log"

	bmodel="$(fm_get "$brief" model)"
	[[ -n "$bmodel" ]] || bmodel="$MODEL"
	btimeout="$(fm_get "$brief" timeout)"
	[[ -n "$btimeout" ]] || btimeout="$TIMEOUT"
	case "$btimeout" in
	'' | *[!0-9hms]*) badt=1 ;;
	*[hms]*[hms]*) badt=1 ;;
	*[hms]) case "${btimeout%?}" in '' | *[!0-9]*) badt=1 ;; *) badt=0 ;; esac ;;
	*) case "$btimeout" in *[!0-9]*) badt=1 ;; *) badt=0 ;; esac ;;
	esac
	if [[ ${badt:-0} -eq 1 ]]; then
		echo "  FAILED(bad-timeout)  [$name]  invalid timeout: '$btimeout'"
		return 1
	fi
	bschema="$(fm_get "$brief" schema)"
	if [[ -n "$bschema" && "$bschema" != /* ]]; then
		bschema="$(cd "$(dirname "$brief")" && pwd)/$bschema"
	fi
	if [[ -n "$bschema" && ! -f "$bschema" ]]; then
		echo "  FAILED(schema-file) [$name] schema not found: $bschema"
		return 1
	fi
	secs="$(duration_to_secs "$btimeout")"

	local prompt
	prompt="$(brief_body "$brief")"

	if [[ -z "${prompt//[[:space:]]/}" ]]; then
		echo "  FAILED(empty-brief)  [$name]  brief body is empty"
		return 1
	fi

	if [[ -n "$bschema" ]]; then
		prompt="$prompt

Your final message must be exactly one JSON object matching this schema, and no other text:
$(cat "$bschema")"
	fi

	if [[ $USE_WORKTREE -eq 1 ]]; then
		workdir="$RESULTS_DIR/worktrees/$name"
		branch="agy/$name"
		mkdir -p "$RESULTS_DIR/worktrees"
		if ! git -C "$REPO" worktree add -b "$branch" "$workdir" "$BASE_REF" >>"$logfile" 2>&1; then
			# Branch may exist from a prior PRUNED run; retry attaching. NOTE: a live
			# leftover worktree still blocks this (git refuses double-checkout) —
			# remove the old worktree first (see footer hint).
			if ! git -C "$REPO" worktree add "$workdir" "$branch" >>"$logfile" 2>&1; then
				echo "  FAILED(worktree)  [$name]  see $logfile"
				return 1
			fi
		fi
	else
		workdir="$REPO"
		branch="(in-place)"
	fi

	# -p BINDS the next token as the prompt (verified live 2026-07-10): the
	# prompt must directly follow -p; every other flag goes AFTER it, or
	# --print swallows the neighboring flag as the prompt text.
	local -a agy_args=(--dangerously-skip-permissions --print-timeout "$btimeout")
	[[ -n "$bmodel" ]] && agy_args+=(--model "$bmodel")

	echo "  launching [$name]  model: ${bmodel:-default}  timeout: $btimeout"
	(
		echo "=== brief: $brief ==="
		echo "=== started: $(date) ==="
		cd "$workdir" || exit 98
		timeout $((secs + 60)) "$AGY_BIN" -p "$prompt" "${agy_args[@]}"
		rc=$?
		echo "=== finished: $(date) (exit $rc) ==="
		exit $rc
	) >>"$logfile" 2>&1 &

	NAMES+=("$name")
	PIDS+=("$!")
	WORKDIRS+=("$workdir")
	BRANCHES+=("$branch")
	SCHEMAS+=("$bschema")
	return 0
}

wait_for_slot() {
	[[ $MAX_PARALLEL -le 0 ]] && return 0
	while :; do
		local alive=0 p
		for p in "${PIDS[@]-}"; do kill -0 "$p" 2>/dev/null && alive=$((alive + 1)); done
		[[ $alive -lt $MAX_PARALLEL ]] && return 0
		sleep 1
	done
}

for brief in "${BRIEFS[@]}"; do
	wait_for_slot
	if run_one "$brief"; then run_count=$((run_count + 1)); else failed_prelaunch=$((failed_prelaunch + 1)); fi
done

echo
echo "Waiting for $run_count agent(s)..."
echo

log_tail_matches_quota() { # LOGFILE -> 0 if quota/auth failure text present
	tail -n 20 "$1" 2>/dev/null | awk '
    BEGIN { IGNORECASE=1 }
    /quota|rate limit|credit|unauthorized|not logged in|login required/ { found=1 }
    END { exit !found }' 2>/dev/null ||
		tail -n 20 "$1" 2>/dev/null | tr 'A-Z' 'a-z' | awk '
    /quota|rate limit|credit|unauthorized|not logged in|login required/ { found=1 }
    END { exit !found }'
}

failed=0
quota_seen=0
for i in "${!PIDS[@]}"; do
	if wait "${PIDS[$i]}"; then
		status="OK"
		schema="${SCHEMAS[$i]}"
		if [[ -n "$schema" && "$SCHEMA_MODE" != "warn" ]]; then
			python3 "$SCRIPT_DIR/validate_output.py" \
				"$RESULTS_DIR/${NAMES[$i]}.log" "$schema" \
				--out "$RESULTS_DIR/${NAMES[$i]}.partial.json"
			vrc=$?
			case "$SCHEMA_MODE:$vrc" in
			*:0) status="OK" ;;
			salvage:2) status="PARTIAL(schema)" ;;
			*)
				status="FAILED(schema)"
				failed=$((failed + 1))
				;;
			esac
		elif [[ -n "$schema" && "$SCHEMA_MODE" == "warn" ]]; then
			python3 "$SCRIPT_DIR/validate_output.py" \
				"$RESULTS_DIR/${NAMES[$i]}.log" "$schema" \
				--out "$RESULTS_DIR/${NAMES[$i]}.partial.json" >/dev/null 2>&1 ||
				echo "  warn: [${NAMES[$i]}] schema violations (see ${NAMES[$i]}.partial.json)"
		fi
	else
		rc=$?
		if [[ $rc -eq 124 ]]; then
			status="FAILED(timeout)"
		elif log_tail_matches_quota "$RESULTS_DIR/${NAMES[$i]}.log"; then
			status="FAILED(quota)"
			quota_seen=1
		else
			status="FAILED(exit)"
		fi
		failed=$((failed + 1))
	fi
	printf "  %-16s [%s]  branch: %-20s log: %s\n" \
		"$status" "${NAMES[$i]}" "${BRANCHES[$i]}" "$RESULTS_DIR/${NAMES[$i]}.log"
done

if [[ $quota_seen -eq 1 ]]; then
	echo "hint: quota/auth failures detected — delegate the remainder via kimi-delegate or native subagents (see SKILL.md fallback policy)."
fi

echo
echo "Done. $((run_count - failed))/$((run_count + failed_prelaunch)) agent(s) succeeded."
if [[ $USE_WORKTREE -eq 1 ]]; then
	echo "Review a branch:   git -C \"$REPO\" diff $BASE_REF..agy/<name>"
	echo "Merge a branch:    git -C \"$REPO\" merge agy/<name>"
	echo "Clean up worktree: git -C \"$REPO\" worktree remove \"$RESULTS_DIR/worktrees/<name>\""
fi
exit $((failed + failed_prelaunch))
