#!/data/data/com.termux/files/usr/bin/bash
source "$(dirname "$0")/helpers.sh"
SCRIPT="$ROOT_DIR/scripts/agy_parallel.sh"
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

report
