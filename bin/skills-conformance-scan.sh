#!/usr/bin/env bash
# Audits an existing UnoPim checkout against the whole rule table in
# hooks/rules.txt, reporting the standing debt per rule and per file.
#
# The edit-time gate is a ratchet: it judges only the lines an edit added, so
# it can never report code that is already committed. This scans whole files
# instead, which is what answers "is the code we already have conformant".
#
# usage: skills-conformance-scan.sh PROJECT [options]
#   --since REF     limit the scan to files changed since REF (a release tag,
#                   a branch, "HEAD~20"); whole files, so pre-existing debt in
#                   a touched file is counted too
#   --diff REF      report ONLY the lines added since REF — the same judgement
#                   the edit-time gate makes, and the right view for reviewing
#                   a branch or a developer's work
#   --path GLOB     limit to paths matching a shell glob, repeatable
#   --rule ID       report only this rule, repeatable
#   --top N         files listed per rule (default 5, 0 for all)
#   --format table|lines|json   default table
#   --fail-on-any   exit 1 when anything is reported, for CI
# Exit 0 when the scan ran, 1 with --fail-on-any and findings, 2 on bad usage.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULES="$HERE/hooks/rules.txt"

PROJECT=""
SINCE=""
DIFF_REF=""
TOP=5
FORMAT=table
FAIL_ON_ANY=""
PATHS=()
ONLY_RULES=()

die() { printf '%s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
    case "$1" in
        --since)  [ $# -ge 2 ] || die "--since needs a git ref";   SINCE="$2"; shift 2 ;;
        --diff)   [ $# -ge 2 ] || die "--diff needs a git ref";     DIFF_REF="$2"; shift 2 ;;
        --path)   [ $# -ge 2 ] || die "--path needs a glob";       PATHS+=("$2"); shift 2 ;;
        --rule)   [ $# -ge 2 ] || die "--rule needs a rule id";    ONLY_RULES+=("$2"); shift 2 ;;
        --top)    [ $# -ge 2 ] || die "--top needs a number";      TOP="$2"; shift 2 ;;
        --format) [ $# -ge 2 ] || die "--format needs a value";    FORMAT="$2"; shift 2 ;;
        --fail-on-any) FAIL_ON_ANY=1; shift ;;
        --rules)  [ $# -ge 2 ] || die "--rules needs a file";      RULES="$2"; shift 2 ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) die "unknown option: $1" ;;
        *)  [ -z "$PROJECT" ] || die "only one PROJECT may be given"; PROJECT="$1"; shift ;;
    esac
done

[ -n "$PROJECT" ] || die "usage: skills-conformance-scan.sh PROJECT [--since REF] [--path GLOB] [--rule ID] [--top N] [--format table|lines|json] [--fail-on-any]"
[ -d "$PROJECT" ] || die "not a directory: $PROJECT"
[ -r "$RULES" ] || die "rule table not readable: $RULES"

case "$FORMAT" in table|lines|json) ;; *) die "unknown format: $FORMAT" ;; esac
printf '%s' "$TOP" | grep -qE '^[0-9]+$' || die "--top needs a number"

PROJECT="$(cd "$PROJECT" && pwd)"

GREP=grep
if ! grep -qP 'x' <<<'x' 2>/dev/null; then
    if command -v ggrep >/dev/null 2>&1 && ggrep -qP 'x' <<<'x' 2>/dev/null; then
        GREP=ggrep
    else
        die "this grep has no -P support, so the PCRE rule table cannot run. Install GNU grep and retry."
    fi
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FILES="$WORK/files"

if [ -n "$DIFF_REF" ]; then
    git -C "$PROJECT" rev-parse --verify "$DIFF_REF" >/dev/null 2>&1 || die "not a git ref in $PROJECT: $DIFF_REF"
    git -C "$PROJECT" diff --name-only "$DIFF_REF" -- > "$FILES" 2>/dev/null
    git -C "$PROJECT" ls-files --others --exclude-standard >> "$FILES" 2>/dev/null
elif [ -n "$SINCE" ]; then
    git -C "$PROJECT" rev-parse --verify "$SINCE" >/dev/null 2>&1 || die "not a git ref in $PROJECT: $SINCE"
    git -C "$PROJECT" diff --name-only "$SINCE" -- > "$FILES" 2>/dev/null
    git -C "$PROJECT" ls-files --others --exclude-standard >> "$FILES" 2>/dev/null
elif git -C "$PROJECT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$PROJECT" ls-files > "$FILES"
    git -C "$PROJECT" ls-files --others --exclude-standard >> "$FILES"
else
    (cd "$PROJECT" && find . -type f | sed 's|^\./||') > "$FILES"
fi

# The gate skips these at edit time; a scan that counted them would report
# thousands of hits in code nobody wrote by hand.
grep -vE '(^|/)(vendor|node_modules|storage|dist|\.git)/|(^|/)public/build/|(^|/)public/themes/.*/build/|\.min\.(js|css)$' "$FILES" \
    | sort -u > "$FILES.clean"
mv "$FILES.clean" "$FILES"

if [ "${#PATHS[@]}" -gt 0 ]; then
    : > "$FILES.filtered"
    while IFS= read -r f; do
        for glob in "${PATHS[@]}"; do
            # shellcheck disable=SC2053
            case "$f" in $glob) printf '%s\n' "$f" >> "$FILES.filtered"; break ;; esac
        done
    done < "$FILES"
    mv "$FILES.filtered" "$FILES"
fi

SCANNED="$(grep -c '' < "$FILES")"
[ "$SCANNED" -gt 0 ] || die "no files to scan"

SCAN_ROOT="$PROJECT"
if [ -n "$DIFF_REF" ]; then
    SCAN_ROOT="$WORK/added"
    mkdir -p "$SCAN_ROOT"
    git -C "$PROJECT" diff -U0 --no-color --no-renames "$DIFF_REF" -- 2>/dev/null \
        | awk -v out="$SCAN_ROOT" '
            /^\+\+\+ b\// { path = substr($0, 7); next }
            /^\+\+\+ / { path = ""; next }
            /^\+/ && path != "" {
                if (!(path in seen)) {
                    n = split(path, parts, "/"); dir = out
                    for (i = 1; i < n; i++) { dir = dir "/" parts[i]; system("mkdir -p \"" dir "\"") }
                    seen[path] = 1
                }
                print substr($0, 2) >> (out "/" path)
            }'
    while IFS= read -r rel; do
        [ -f "$SCAN_ROOT/$rel" ] && continue
        [ -f "$PROJECT/$rel" ] || continue
        git -C "$PROJECT" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 && continue
        mkdir -p "$SCAN_ROOT/$(dirname "$rel")"
        cp "$PROJECT/$rel" "$SCAN_ROOT/$rel"
    done < "$FILES"
fi

wanted() {
    [ "${#ONLY_RULES[@]}" -eq 0 ] && return 0
    local r
    for r in "${ONLY_RULES[@]}"; do [ "$r" = "$1" ] && return 0; done
    return 1
}

REPORT="$WORK/report"
: > "$REPORT"
TOTAL_HITS=0
RULES_HIT=0

while IFS='~' read -r id path_re content_re message || [ -n "${id:-}" ]; do
    case "${id:-}" in ''|'#'*) continue ;; esac
    [ -n "${path_re:-}" ] && [ -n "${content_re:-}" ] || continue
    wanted "$id" || continue

    "$GREP" -P -- "$path_re" "$FILES" > "$WORK/subset" 2>/dev/null
    [ -s "$WORK/subset" ] || continue

    if true; then
        (cd "$SCAN_ROOT" && tr '\n' '\0' < "$WORK/subset" \
            | xargs -0 -r "$GREP" -HnP -- "$content_re" 2>/dev/null) > "$WORK/hits" || true
    fi
    hits="$(grep -c '' < "$WORK/hits")"
    [ "$hits" -gt 0 ] || continue

    files="$(cut -d: -f1 < "$WORK/hits" | sort -u | grep -c '')"
    TOTAL_HITS=$((TOTAL_HITS + hits))
    RULES_HIT=$((RULES_HIT + 1))

    {
        printf 'RULE\t%s\t%s\t%s\t%s\n' "$id" "$hits" "$files" "${message:-}"
        ranked="$(cut -d: -f1 < "$WORK/hits" | sort | uniq -c | sort -rn)"
        [ "$TOP" -gt 0 ] && ranked="$(printf '%s\n' "$ranked" | head -"$TOP")"
        printf '%s\n' "$ranked" | while read -r count path; do
            [ -n "$path" ] && printf 'FILE\t%s\t%s\n' "$count" "$path"
        done
        if [ "$FORMAT" = lines ]; then
            head -20 < "$WORK/hits" | cut -c1-200 \
                | while IFS= read -r line; do printf 'LINE\t%s\n' "$line"; done
        fi
    } >> "$REPORT"
done < "$RULES"

case "$FORMAT" in
json)
    python3 - "$REPORT" "$PROJECT" "$SCANNED" "$TOTAL_HITS" <<'PY'
import json, sys
report, project, scanned, total = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
rules, current = [], None
for raw in open(report):
    line = raw.rstrip('\n')
    if line.startswith('FILE\t'):
        _, count, path = line.split('\t', 2)
        current['files'].append({'path': path, 'hits': int(count)})
    elif line.startswith('LINE\t'):
        current['samples'].append(line.split('\t', 1)[1])
    elif line.startswith('RULE\t'):
        _, rid, hits, files, message = line.split('\t', 4)
        current = {'rule': rid, 'hits': int(hits), 'files_affected': int(files),
                   'message': message, 'files': [], 'samples': []}
        rules.append(current)
print(json.dumps({'project': project, 'files_scanned': scanned,
                  'total_findings': total, 'rules': rules}, indent=2))
PY
    ;;
*)
    printf 'UnoPim conformance scan\n'
    printf '  project : %s\n' "$PROJECT"
    [ -n "$SINCE" ] && printf '  since   : %s (whole files)\n' "$SINCE"
    [ -n "$DIFF_REF" ] && printf '  diff    : lines added since %s\n' "$DIFF_REF"
    printf '  scanned : %s files against %s rules\n\n' "$SCANNED" \
        "$(grep -cvE '^\s*(#|$)' "$RULES")"

    if [ "$TOTAL_HITS" -eq 0 ]; then
        printf 'No findings. Every scanned file is clean against the rule table.\n'
    else
        printf '%-24s %8s %8s\n' RULE FINDINGS FILES
        printf '%-24s %8s %8s\n' '------------------------' -------- --------
        while IFS=$'\t' read -r kind a b c MSG; do
            case "$kind" in
                RULE) printf '\n%-24s %8s %8s\n' "$a" "$b" "$c"
                      printf '%s\n' "$MSG" | fold -s -w 92 | sed 's/^/    /' ;;
                FILE) printf '%25s %7s  %s\n' '' "$a" "$b" ;;
                LINE) printf '%25s %s\n' '' "$a" ;;
            esac
        done < "$REPORT"
        printf '\n%s findings across %s rules.\n' "$TOTAL_HITS" "$RULES_HIT"
        if [ -n "$DIFF_REF" ]; then
            printf 'These are violations this work ADDED, judged the same way the edit-time\n'
            printf 'gate judges them. Unlike standing debt, every one of these is fair to\n'
            printf 'ask for before merge.\n'
        else
            printf 'This is standing debt, not a verdict on any one change: the edit-time gate\n'
            printf 'blocks only NEW violations, so this list can shrink but never has to be\n'
            printf 'cleared before shipping. Fix by rule, highest-count file first.\n'
        fi
    fi
    ;;
esac

[ -n "$FAIL_ON_ANY" ] && [ "$TOTAL_HITS" -gt 0 ] && exit 1
exit 0
