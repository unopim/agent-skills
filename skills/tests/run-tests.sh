#!/usr/bin/env bash
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
export FIXTURES="$TESTS_DIR/fixtures"
FAILED=0

assert_passes() {
    if "$@" >/dev/null 2>&1; then
        echo "  ok   : $*"
    else
        echo "  FAIL : expected success: $*"
        FAILED=1
    fi
}

assert_fails() {
    if "$@" >/dev/null 2>&1; then
        echo "  FAIL : expected failure: $*"
        FAILED=1
    else
        echo "  ok   : $*"
    fi
}

assert_output_contains() {
    local needle="$1"; shift
    local out
    out="$("$@" 2>&1)"
    if printf '%s' "$out" | grep -qF -- "$needle"; then
        echo "  ok   : output contains '$needle'"
    else
        echo "  FAIL : output missing '$needle' from: $*"
        printf '%s\n' "$out" | sed 's/^/         /'
        FAILED=1
    fi
}

export -f assert_passes assert_fails assert_output_contains

for t in "$TESTS_DIR"/*.test.sh; do
    echo "== $(basename "$t")"
    # shellcheck disable=SC1090
    source "$t"
done

exit "$FAILED"
