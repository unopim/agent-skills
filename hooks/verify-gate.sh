#!/usr/bin/env bash
# Stop gate: blocks a completion claim (exit 2) when PHP, Blade, Vue, JS or
# translation files changed after unopim-verify last passed. The stamp is
# PROJECT_ROOT/.verify-stamp, a single integer of unix seconds. Exits 0 when
# the checkout is not a git repository or nothing relevant changed.
#
#   verify-gate.sh --baseline   SessionStart: records the relevant files
#                               already dirty, and their mtimes, so a branch
#                               that arrived dirty is never mistaken for this
#                               session's work. Silent, always exit 0.
#   verify-gate.sh              Stop: exit 2 when a file THIS session changed
#                               has not been verified since.
set -uo pipefail

MODE=stop
case "${1:-}" in
    '') ;;
    --baseline) MODE=baseline ;;
    *) printf 'usage: verify-gate.sh [--baseline]\n' >&2; exit 2 ;;
esac

PAYLOAD=""
[ -t 0 ] || PAYLOAD="$(cat 2>/dev/null)"

SESSION=""
STOP_ACTIVE=""
if [ -n "$PAYLOAD" ]; then
    read -r SESSION STOP_ACTIVE <<EOF
$(printf '%s' "$PAYLOAD" | python3 -c '
import json, sys
session, active = "-", "no"
try:
    data = json.load(sys.stdin)
except Exception:
    data = None
if isinstance(data, dict):
    raw = data.get("session_id")
    if isinstance(raw, str):
        clean = "".join(c for c in raw if c.isalnum() or c in "-_")[:64]
        session = clean or "-"
    if data.get("stop_hook_active"):
        active = "yes"
print(session, active)
' 2>/dev/null)
EOF
fi
[ -n "$SESSION" ] || SESSION="-"
[ "$STOP_ACTIVE" = yes ] || STOP_ACTIVE=no

if [ "$MODE" = stop ] && [ "$STOP_ACTIVE" = yes ]; then
    exit 0
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

KEY="$(printf '%s' "$TOP" | cksum | tr -cd '0-9' | cut -c1-12)"
STATE="${TMPDIR:-/tmp}/unopim-verify-${SESSION}-${KEY}"

# path<TAB>mtime for everything already dirty, so a later edit to the same file
# still counts: the mtime moves, the recorded one does not.
snapshot() {
    printf '%s\n' "$RELEVANT" | python3 -c '
import os, sys
for line in sys.stdin:
    path = line.strip()
    if not path:
        continue
    try:
        print("%s\t%d" % (path, int(os.path.getmtime(path))))
    except OSError:
        pass
' 2>/dev/null
}

# A branch that was dirty before the session started is not this session's work
# to verify. Without a baseline the gate cannot tell the two apart, so it
# records one and passes rather than blocking on someone else's changes — the
# same contract as the sweep. Installing the hooks mid-session is the usual way
# to arrive here.
# An EMPTY baseline is the meaningful one: it records that nothing relevant was
# dirty when the session began, so the first file the session touches is its
# own. Writing the state only when something was already dirty would let that
# first file establish the baseline and forgive itself.
if [ "$MODE" = baseline ] || [ ! -f "$STATE" ]; then
    if [ ! -f "$STATE" ]; then
        SCRATCH="$(mktemp "${STATE}.XXXXXX" 2>/dev/null)" || exit 0
        snapshot > "$SCRATCH" 2>/dev/null
        mv -f "$SCRATCH" "$STATE" 2>/dev/null || rm -f "$SCRATCH"
    fi
    exit 0
fi

[ -n "$RELEVANT" ] || exit 0

RELEVANT="$(snapshot | python3 -c '
import sys
baseline = {}
try:
    with open(sys.argv[1]) as handle:
        for line in handle:
            path, _, mtime = line.rstrip("\n").partition("\t")
            if path:
                try:
                    baseline[path] = int(mtime)
                except ValueError:
                    baseline[path] = 0
except OSError:
    pass
for line in sys.stdin:
    path, _, mtime = line.rstrip("\n").partition("\t")
    if not path:
        continue
    try:
        current = int(mtime)
    except ValueError:
        continue
    if path not in baseline or current > baseline[path]:
        print(path)
' "$STATE" 2>/dev/null)"
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
