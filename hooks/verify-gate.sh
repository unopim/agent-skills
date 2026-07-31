#!/usr/bin/env bash
# Stop gate: blocks a completion claim (exit 2) when PHP, Blade, Vue, JS or
# translation files changed after unopim-verify last passed. The stamp is
# PROJECT_ROOT/.verify-stamp, a single integer of unix seconds. Exits 0 when
# the checkout is not a git repository or nothing relevant changed.
set -uo pipefail

if [ ! -t 0 ]; then
    ACTIVE="$(python3 -c '
import json, sys
try:
    print("yes" if json.load(sys.stdin).get("stop_hook_active") else "no")
except Exception:
    print("no")
' 2>/dev/null)"
    [ "$ACTIVE" = "yes" ] && exit 0
fi

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -d "$ROOT" ] || exit 0
cd "$ROOT" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

TOP="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$TOP" ] || exit 0
cd "$TOP" 2>/dev/null || exit 0

if git rev-parse --verify HEAD >/dev/null 2>&1; then
    CHANGED="$(git diff --name-only HEAD; git ls-files --others --exclude-standard)"
else
    CHANGED="$(git ls-files --others --exclude-standard)"
fi

RELEVANT="$(printf '%s\n' "$CHANGED" \
    | grep -E '\.(php|vue|js|ts)$|Resources/lang/' \
    | sort -u)"
[ -n "$RELEVANT" ] || exit 0

STAMP_FILE=""
for candidate in "$ROOT/.verify-stamp" "$TOP/.verify-stamp"; do
    if [ -f "$candidate" ]; then
        STAMP_FILE="$candidate"
        break
    fi
done

# The stamp must be exactly one integer of unix seconds, which is what
# unopim-verify/verify.sh writes. Anything else is not a stamp and must fail
# CLOSED: stripping the non-digits out of "1785422223.437" instead would yield
# 1785422223437, a timestamp forty thousand years from now, and the gate would
# then never block again.
STAMP=""
if [ -n "$STAMP_FILE" ]; then
    STAMP="$(head -1 "$STAMP_FILE" 2>/dev/null | tr -d '[:space:]')"
    case "$STAMP" in
        ''|*[!0-9]*) STAMP="" ;;
        *) [ "${#STAMP}" -le 18 ] || STAMP="" ;;
    esac
fi

block() {
    {
        printf '%s\n' "verify-gate: $1"
        echo
        printf '%s\n' "$RELEVANT" | head -20 | sed 's/^/    /'
        echo
        echo "Run the unopim-verify gates and let them pass before claiming this"
        echo "is done. Fix the root cause of a failure; do not suppress it."
    } >&2
    exit 2
}

if [ -z "$STAMP" ]; then
    block "relevant files changed and verification has never passed in this checkout."
fi

NEWEST="$(printf '%s\n' "$RELEVANT" | python3 -c '
import os, sys
newest = 0
for line in sys.stdin:
    path = line.strip()
    if not path:
        continue
    try:
        newest = max(newest, int(os.path.getmtime(path)))
    except OSError:
        pass
print(newest)
' 2>/dev/null)"

case "$NEWEST" in
    ''|*[!0-9]*) exit 0 ;;
esac

if [ "$NEWEST" -gt "$STAMP" ]; then
    block "files changed after the last passing verification."
fi

exit 0
