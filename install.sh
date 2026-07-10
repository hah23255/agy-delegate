#!/data/data/com.termux/files/usr/bin/bash
# Install agy-delegate by symlinking this repo into the Claude skills dir.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
DEST="$DEST_DIR/agy-delegate"
mkdir -p "$DEST_DIR"
if [[ -e "$DEST" && ! -L "$DEST" ]]; then
	echo "error: $DEST exists and is not a symlink — remove it manually" >&2
	exit 1
fi
ln -sfn "$SRC" "$DEST"
echo "installed: $DEST -> $SRC (version $(cat "$SRC/VERSION"))"
