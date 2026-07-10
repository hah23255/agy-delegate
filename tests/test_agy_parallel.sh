#!/data/data/com.termux/files/usr/bin/bash
source "$(dirname "$0")/helpers.sh"
SCRIPT="$ROOT_DIR/scripts/agy_parallel.sh"
SCRIPT_SRC_HELPER="$ROOT_DIR/scripts/agy_lib.sh"
export AGY_BIN="$TESTS_DIR/stubs/agy"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkbrief() { # path — writes a lint-passing brief
	cat >"$1" <<'EOF'
## Goal
Do the thing.
## Scope
Only file x.
## Requirements
Exact behavior.
## Verification
Run tests.
EOF
}

# --- help ---
out="$(bash "$SCRIPT" --help)"
assert_eq "$?" "0" "--help exits 0"
assert_contains "$out" "--schema-mode" "help documents schema-mode"

# --- preflight: no briefs ---
err="$(bash "$SCRIPT" --repo "$TMP" 2>&1)"
assert_eq "$?" "1" "no briefs -> exit 1"
assert_contains "$err" "no brief" "no-briefs error message"

# --- preflight: missing brief file ---
err="$(bash "$SCRIPT" --repo "$TMP" "$TMP/nope.md" 2>&1)"
assert_eq "$?" "1" "missing brief -> exit 1"

# --- preflight: bad repo ---
mkbrief "$TMP/a.md"
err="$(bash "$SCRIPT" --repo "$TMP/does-not-exist" "$TMP/a.md" 2>&1)"
assert_eq "$?" "1" "bad repo -> exit 1"

# --- preflight: unknown flag ---
err="$(bash "$SCRIPT" --bogus 2>&1)"
assert_eq "$?" "1" "unknown option -> exit 1"

# --- lint: reject brief missing sections ---
printf '## Goal\nonly a goal\n' >"$TMP/bad.md"
err="$(bash "$SCRIPT" --repo "$TMP" "$TMP/bad.md" 2>&1)"
assert_eq "$?" "1" "lint rejects incomplete brief"
assert_contains "$err" "## Scope" "lint names missing section"

# --- lint bypass ---
# (runs the launch path; stub agy makes it succeed)
git -C "$TMP" init -q -b main 2>/dev/null || true
out="$(cd "$TMP" && AGY_STUB_ARGS="$TMP/args.txt" bash "$SCRIPT" --repo "$TMP" --no-worktree --no-lint "$TMP/bad.md" 2>&1)"
assert_eq "$?" "0" "--no-lint bypasses lint"

# --- lint: prefix superset does not satisfy required section (review fix) ---
printf '## Goals\ng\n## Scope\ns\n## Requirements\nr\n## Verification\nv\n' >"$TMP/prefix.md"
err="$(bash "$SCRIPT" --repo "$TMP" "$TMP/prefix.md" 2>&1)"
assert_eq "$?" "1" "lint rejects ## Goals for ## Goal"

# --- frontmatter: model/timeout/schema extraction ---
cat >"$TMP/fm.md" <<'EOF'
---
model: Gemini 3.1 Pro (High)
timeout: 20m
schema: my-schema.json
---
## Goal
g
## Scope
s
## Requirements
r
## Verification
v
EOF
source_out="$(bash -c "source '$SCRIPT_SRC_HELPER'; fm_get '$TMP/fm.md' model")"
assert_eq "$source_out" "Gemini 3.1 Pro (High)" "fm_get model"
assert_eq "$(bash -c "source '$SCRIPT_SRC_HELPER'; fm_get '$TMP/fm.md' timeout")" "20m" "fm_get timeout"
assert_eq "$(bash -c "source '$SCRIPT_SRC_HELPER'; fm_get '$TMP/a.md' model")" "" "fm_get absent frontmatter"
body="$(bash -c "source '$SCRIPT_SRC_HELPER'; brief_body '$TMP/fm.md'")"
assert_contains "$body" "## Goal" "brief_body keeps content"
case "$body" in *"model:"*)
	FAIL=$((FAIL + 1))
	echo "FAIL: brief_body leaks frontmatter"
	;;
*) PASS=$((PASS + 1)) ;; esac

# --- brief_body: unterminated frontmatter treated as body (review fix) ---
printf -- '---\nmodel: x\n## Goal\ng\n' >"$TMP/unterm.md"
body_u="$(bash -c "source '$SCRIPT_SRC_HELPER'; brief_body '$TMP/unterm.md'")"
assert_contains "$body_u" "## Goal" "unterminated fm: body preserved"

# --- launch: happy path, two briefs, logs + args recorded ---
LAUNCH="$TMP/launch"
mkdir -p "$LAUNCH"
cd "$LAUNCH"
git init -q -b main
git commit -q --allow-empty -m init
mkbrief "$LAUNCH/one.md"
mkbrief "$LAUNCH/two.md"
ARGS="$TMP/launch-args.txt"
: >"$ARGS"
echo "stub says hi" >"$TMP/stub-out.txt"
out="$(AGY_STUB_ARGS="$ARGS" AGY_STUB_STDOUT="$TMP/stub-out.txt" \
	bash "$SCRIPT" --repo "$LAUNCH" --no-worktree --results-dir "$TMP/run1" \
	--model "Gemini 3.5 Flash (High)" "$LAUNCH/one.md" "$LAUNCH/two.md" 2>&1)"
assert_eq "$?" "0" "all agents OK -> exit 0"
assert_file_exists "$TMP/run1/one.log" "log for brief one"
assert_file_exists "$TMP/run1/two.log" "log for brief two"
assert_file_exists "$TMP/run1/meta.txt" "meta.txt written"
assert_contains "$(cat "$TMP/run1/one.log")" "stub says hi" "agent stdout teed to log"
assert_contains "$(cat "$ARGS")" "--print" "agy called with --print"
assert_contains "$(cat "$ARGS")" "--dangerously-skip-permissions" "auto-approve flag passed"
assert_contains "$(cat "$ARGS")" "Gemini 3.5 Flash (High)" "model flag passed intact"
assert_contains "$out" "OK" "summary shows OK"

# --- frontmatter model override beats --model flag ---
cat >"$LAUNCH/fmodel.md" <<'EOF'
---
model: Claude Opus 4.6 (Thinking)
---
## Goal
g
## Scope
s
## Requirements
r
## Verification
v
EOF
: >"$ARGS"
AGY_STUB_ARGS="$ARGS" bash "$SCRIPT" --repo "$LAUNCH" --no-worktree \
	--results-dir "$TMP/run2" --model "Gemini 3.5 Flash (High)" "$LAUNCH/fmodel.md" >/dev/null 2>&1
assert_contains "$(cat "$ARGS")" "Claude Opus 4.6 (Thinking)" "frontmatter model wins"

# --- failure aggregation: exit = #failed ---
out="$(AGY_STUB_EXIT=7 bash "$SCRIPT" --repo "$LAUNCH" --no-worktree \
	--results-dir "$TMP/run3" "$LAUNCH/one.md" "$LAUNCH/two.md" 2>&1)"
assert_eq "$?" "2" "two failures -> exit 2"
assert_contains "$out" "FAILED(exit)" "summary shows FAILED(exit)"

# --- quota refinement ---
echo "Error: quota exceeded for this billing period" >"$TMP/quota-out.txt"
out="$(AGY_STUB_EXIT=1 AGY_STUB_STDOUT="$TMP/quota-out.txt" bash "$SCRIPT" \
	--repo "$LAUNCH" --no-worktree --results-dir "$TMP/run4" "$LAUNCH/one.md" 2>&1)"
assert_eq "$?" "1" "quota failure counts as failed"
assert_contains "$out" "FAILED(quota)" "quota detected from log"

# --- throttle: --max-parallel 1 serializes ---
start=$(date +%s)
AGY_STUB_SLEEP=2 bash "$SCRIPT" --repo "$LAUNCH" --no-worktree \
	--results-dir "$TMP/run5" --max-parallel 1 "$LAUNCH/one.md" "$LAUNCH/two.md" >/dev/null 2>&1
elapsed=$(($(date +%s) - start))
if [[ $elapsed -ge 4 ]]; then
	PASS=$((PASS + 1))
else
	FAIL=$((FAIL + 1))
	echo "FAIL: throttle — expected >=4s serialized, got ${elapsed}s"
fi

# --- empty brief (no schema) fails the run (review fix) ---
printf -- '---\nmodel: x\n---\n\n' >"$LAUNCH/empty.md"
out="$(bash "$SCRIPT" --repo "$LAUNCH" --no-worktree --no-lint --results-dir "$TMP/run-e1" "$LAUNCH/empty.md" 2>&1)"
assert_eq "$?" "1" "empty brief -> exit 1"
assert_contains "$out" "FAILED(empty-brief)" "empty brief status shown"

# --- empty brief WITH schema still fails (guard precedes suffix) (review fix) ---
printf '{"type":"object","properties":{"x":{"type":"string"}}}\n' >"$LAUNCH/empty-schema.json"
printf -- '---\nschema: empty-schema.json\n---\n\n' >"$LAUNCH/empty2.md"
out="$(bash "$SCRIPT" --repo "$LAUNCH" --no-worktree --no-lint --results-dir "$TMP/run-e2" "$LAUNCH/empty2.md" 2>&1)"
assert_eq "$?" "1" "empty brief with schema -> exit 1"
assert_contains "$out" "FAILED(empty-brief)" "schema does not mask empty brief"

# --- worktree: per-brief branch + agent runs inside it ---
: >"$ARGS"
out="$(AGY_STUB_ARGS="$ARGS" bash "$SCRIPT" --repo "$LAUNCH" \
	--results-dir "$TMP/run6" "$LAUNCH/one.md" 2>&1)"
assert_eq "$?" "0" "worktree run OK"
assert_file_exists "$TMP/run6/worktrees/one" "worktree dir created"
assert_eq "$(git -C "$LAUNCH" branch --list 'agy/one' | tr -d ' *+')" "agy/one" "branch agy/one exists"
assert_contains "$out" "git -C" "summary prints review commands"

# --- worktree failure -> FAILED(worktree), no agent launched ---
out="$(bash "$SCRIPT" --repo "$LAUNCH" --base "no-such-ref" \
	--results-dir "$TMP/run7" "$LAUNCH/two.md" 2>&1)"
assert_eq "$?" "1" "bad base ref -> 1 failure"
assert_contains "$out" "FAILED(worktree)" "worktree failure reported"

report
