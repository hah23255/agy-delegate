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

report
