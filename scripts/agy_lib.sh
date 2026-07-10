#!/data/data/com.termux/files/usr/bin/bash
# agy_lib.sh — pure helper functions for agy_parallel.sh (no side effects on source).

# All three helpers strip a trailing CR first so CRLF briefs parse the same as
# LF briefs (D4) — otherwise the marker line reads "---\r" and never matches.
fm_get() { # FILE KEY -> print frontmatter value or nothing
	awk -v key="$2" '
    { sub(/\r$/, "") }
    NR==1 && $0 != "---" { exit }
    NR==1 { infm=1; next }
    infm && $0 == "---" { exit }
    infm && index($0, key ":") == 1 {
      v = substr($0, length(key) + 2)
      sub(/^[ \t]+/, "", v); print v; exit
    }' "$1"
}

brief_body() { # FILE -> print brief with frontmatter stripped
	awk '
    { sub(/\r$/, "") }
    NR==1 && $0 != "---" { nofm=1 }
    nofm { print; next }
    NR==1 { infm=1; buf[bn++]=$0; next }
    infm && $0 == "---" { infm=0; body=1; bn=0; next }
    infm { buf[bn++]=$0; next }
    body { print }
    END { if (infm) for (i=0; i<bn; i++) print buf[i] }' "$1"
}

lint_brief() { # FILE -> 0 if all required sections present, else 1 + stderr
	local f="$1" missing=""
	local sec
	for sec in "## Goal" "## Scope" "## Requirements" "## Verification"; do
		if ! awk -v s="$sec" '{ line=$0; sub(/[ \t\r]+$/, "", line) } line == s { found=1 } END { exit !found }' "$f"; then
			missing="$missing $sec;"
		fi
	done
	if [[ -n "$missing" ]]; then
		echo "error: brief $f is missing required sections:$missing (use --no-lint to bypass)" >&2
		return 1
	fi
	return 0
}

duration_to_secs() { # Go-style single-unit duration -> seconds
	case "$1" in
	*h) echo $((10#${1%h} * 3600)) ;;
	*m) echo $((10#${1%m} * 60)) ;;
	*s) echo $((10#${1%s})) ;;
	*) echo "$1" ;;
	esac
}

sanitize_name() { # printf avoids trailing-newline artifacts (kimi lesson)
	printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'
}
