#!/usr/bin/env bash
# Claude Code Stop gate: the working-tree sweep.
#
# The edit-time ratchet is registered on Edit and Write, so a file written with
# a Bash redirect, sed -i, tee or a script never reaches it, and a violation
# whose block message was read but not acted on stays on disk. This applies the
# whole rule table to every line added since the session started, whatever
# wrote them, using bin/skills-conformance-scan.sh --diff as the engine so the
# sweep and the scan can never drift apart.
#
#   sweep-gate.sh --baseline   SessionStart: records the violations already in
#                              the tree and the commit it is measuring from, so
#                              only what THIS session adds is ever reported.
#                              Silent, always exit 0, never overwrites.
#   sweep-gate.sh              Stop: exit 2 naming each rule, how many lines it
#                              matched and in which files. Exit 0 when the
#                              session added nothing new.
#
# Exit 0 on anything it cannot judge: not a git repository, no commits, an
# unchanged tree, or a payload that says a Stop hook is already driving.
set -uo pipefail

MODE=stop
case "${1:-}" in
    '') ;;
    --baseline) MODE=baseline ;;
    *) printf 'usage: sweep-gate.sh [--baseline]\n' >&2; exit 2 ;;
esac

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RULES="$HERE/rules.txt"
[ -r "$RULES" ] || RULES="$HERE/../hooks/rules.txt"

ENGINE=""
for candidate in "$HERE/skills-conformance-scan.sh" "$HERE/../bin/skills-conformance-scan.sh"; do
    if [ -x "$candidate" ]; then
        ENGINE="$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")"
        break
    fi
done

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

HEAD_SHA="$(git rev-parse --verify HEAD 2>/dev/null)"
[ -n "$HEAD_SHA" ] || exit 0

KEY="$(printf '%s' "$TOP" | cksum | tr -cd '0-9' | cut -c1-12)"
STATE="${TMPDIR:-/tmp}/unopim-sweep-${SESSION}-${KEY}"

changed_since() {
    {
        git diff --name-only "$1" -- 2>/dev/null
        git ls-files --others --exclude-standard 2>/dev/null
    } | head -1
}

# The engine judges repository-relative paths while the edit-time gate judges
# absolute ones, so the /[Tt]ests?/ exclusion every rule in the table carries
# does not fire on a top-level tests/ directory. Dropping those paths here is
# what keeps the sweep's verdict identical to the gate's.
scan_counts() {
    "$ENGINE" "$TOP" --diff "$1" --rules "$RULES" --top 0 --format json 2>/dev/null \
        | python3 -c '
import json, re, sys
skip = re.compile(r"(^|/)[Tt]ests?/|\.spec\.|\.test\.")
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if not isinstance(data, dict):
    sys.exit(0)
for rule in data.get("rules", []):
    name = str(rule.get("rule", "")).strip()
    if not name:
        continue
    message = " ".join(str(rule.get("message", "")).split())
    for entry in rule.get("files", []):
        path = str(entry.get("path", ""))
        if not path or skip.search(path):
            continue
        print("%s\t%s\t%d\t%s" % (name, path, int(entry.get("hits", 0)), message))
' 2>/dev/null
}

if [ "$MODE" = baseline ]; then
    [ -f "$STATE" ] && exit 0
    SCRATCH="$(mktemp "${STATE}.XXXXXX" 2>/dev/null)" || exit 0
    printf 'REF\t%s\t0\t\n' "$HEAD_SHA" > "$SCRATCH"
    if [ -n "$ENGINE" ] && [ -n "$(changed_since "$HEAD_SHA")" ]; then
        scan_counts "$HEAD_SHA" >> "$SCRATCH"
    fi
    mv -f "$SCRATCH" "$STATE" 2>/dev/null || rm -f "$SCRATCH"
    exit 0
fi

# No baseline means the SessionStart hook never ran for this session — the
# usual cause is installing the hooks into a checkout that a session already
# had open. Everything already in the tree would then be attributed to this
# session, so record the baseline now and pass: a sweep that cannot tell the
# session's work from the branch's is a sweep with nothing to say.
if [ ! -f "$STATE" ]; then
    exec "$0" --baseline <<EOF
$PAYLOAD
EOF
fi

# Measuring from the commit the session started on, not from HEAD, is what
# stops "write it with a redirect, then commit it" from erasing the evidence.
BASE_REF="$HEAD_SHA"
if [ -f "$STATE" ]; then
    RECORDED="$(awk -F'\t' '$1 == "REF" { print $2; exit }' "$STATE" 2>/dev/null)"
    if [ -n "$RECORDED" ] && git merge-base --is-ancestor "$RECORDED" HEAD >/dev/null 2>&1; then
        BASE_REF="$RECORDED"
    fi
fi

[ -n "$(changed_since "$BASE_REF")" ] || exit 0

if [ -z "$ENGINE" ]; then
    {
        echo "sweep-gate: skills-conformance-scan.sh is not installed beside this hook,"
        echo "so the working tree was NOT swept and only Edit/Write were checked."
        echo "Run bin/install-hooks.sh against this checkout to restore the sweep."
    } >&2
    exit 1
fi

CURRENT="$(scan_counts "$BASE_REF")"
[ -n "$CURRENT" ] || exit 0

# The sentinel keeps this file non-empty. awk's NR==FNR idiom silently treats
# the whole SECOND file as the first when the first has no records, which would
# make every finding look like pre-existing debt and the sweep would never fire.
BASE_COUNTS="$(mktemp)" || exit 0
printf 'SENTINEL\t-\t0\t\n' > "$BASE_COUNTS"
if [ -f "$STATE" ]; then
    grep -v '^REF	' "$STATE" >> "$BASE_COUNTS" 2>/dev/null
fi

NEW="$(printf '%s\n' "$CURRENT" | awk -F'\t' '
    NR == FNR { if (NF >= 3) base[$1 SUBSEP $2] = $3; next }
    NF >= 3 {
        key = $1 SUBSEP $2
        prior = (key in base) ? base[key] : 0
        delta = $3 - prior
        if (delta > 0) printf "%s\t%s\t%d\t%s\n", $1, $2, delta, $4
    }
' "$BASE_COUNTS" -)"
rm -f "$BASE_COUNTS"

[ -n "$NEW" ] || exit 0

SHORT_REF="$(git rev-parse --short "$BASE_REF" 2>/dev/null || printf '%s' "$BASE_REF")"
ENGINE_HINT="${ENGINE#"$TOP"/}"

{
    printf '%s\n' "$NEW" | awk -F'\t' '
        {
            rule = $1
            if (!(rule in total)) { order[++rules] = rule; message[rule] = $4 }
            total[rule] += $3
            count = ++files[rule]
            if (count <= 6) detail[rule, count] = sprintf("%s (%d)", $2, $3)
        }
        END {
            grand = 0
            for (i = 1; i <= rules; i++) grand += total[order[i]]
            printf "sweep-gate BLOCKED: %d line(s) this session added violate %d rule(s).\n\n", grand, rules
            for (i = 1; i <= rules && i <= 8; i++) {
                rule = order[i]
                printf "  %s: %d line(s) added, %d file(s)\n", rule, total[rule], files[rule]
                for (j = 1; j <= files[rule] && j <= 6; j++) printf "      %s\n", detail[rule, j]
                if (files[rule] > 6) printf "      ... and %d more file(s)\n", files[rule] - 6
                printf "      %s\n\n", message[rule]
            }
            if (rules > 8) printf "  ... and %d further rule(s); the scan command below lists them.\n\n", rules - 8
        }'
    printf 'These are lines added since %s, minus everything already in the tree when\n' "$SHORT_REF"
    printf 'this session started, so none of it is pre-existing debt and none of it is\n'
    printf 'something you already fixed. The edit-time gate never saw them: it is\n'
    printf 'registered on Edit and Write, so anything written another way, or written\n'
    printf 'and then committed, arrives here instead.\n\n'
    printf 'Fix them and stop again. To read the exact lines of one rule:\n'
    printf '  %s . --diff %s --format lines --rule RULE_ID\n' "$ENGINE_HINT" "$SHORT_REF"
} >&2

exit 2
