#!/data/data/com.termux/files/usr/bin/bash
# Shared assert harness for agy-delegate bash tests.
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$TESTS_DIR")"
PASS=0
FAIL=0

assert_eq() { # actual expected label
	if [[ "$1" == "$2" ]]; then
		PASS=$((PASS + 1))
	else
		FAIL=$((FAIL + 1))
		echo "FAIL: $3"
		echo "  expected: [$2]"
		echo "  actual:   [$1]"
	fi
}
assert_contains() { # haystack needle label
	case "$1" in *"$2"*) PASS=$((PASS + 1)) ;;
	*)
		FAIL=$((FAIL + 1))
		echo "FAIL: $3"
		echo "  [$1] does not contain [$2]"
		;;
	esac
}
assert_file_exists() { # path label
	if [[ -e "$1" ]]; then
		PASS=$((PASS + 1))
	else
		FAIL=$((FAIL + 1))
		echo "FAIL: $2 — missing $1"
	fi
}
report() {
	echo
	echo "== $PASS passed, $FAIL failed =="
	[[ $FAIL -eq 0 ]] || exit 1
}
