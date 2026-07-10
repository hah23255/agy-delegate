#!/data/data/com.termux/files/usr/bin/bash
source "$(dirname "$0")/helpers.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# install.sh creates a symlink <skills-dir>/agy-delegate -> repo root
CLAUDE_SKILLS_DIR="$TMP/skills" bash "$ROOT_DIR/install.sh" >"$TMP/out.txt" 2>&1
assert_eq "$?" "0" "install.sh exits 0"
assert_eq "$(readlink "$TMP/skills/agy-delegate")" "$ROOT_DIR" "symlink points at repo"
assert_contains "$(cat "$TMP/out.txt")" "0.1.0" "prints version"

# re-running is idempotent
CLAUDE_SKILLS_DIR="$TMP/skills" bash "$ROOT_DIR/install.sh" >/dev/null 2>&1
assert_eq "$?" "0" "re-install idempotent"

# refuses to clobber a real directory
mkdir -p "$TMP/skills2/agy-delegate"
CLAUDE_SKILLS_DIR="$TMP/skills2" bash "$ROOT_DIR/install.sh" >/dev/null 2>&1
assert_eq "$?" "1" "refuses non-symlink destination"

report
