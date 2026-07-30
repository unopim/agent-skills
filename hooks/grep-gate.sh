#!/usr/bin/env bash
# Claude Code PostToolUse gate: the ratchet.
# Reads the hook payload on stdin and exits 2 when a line THIS EDIT ADDED
# matches a rule in rules.txt, naming the rule, the fix and the offending
# lines on stderr. Committed violations are never reported, so legacy debt
# never blocks an edit while the debt can never grow.
# Exit 0 on anything it cannot judge: no payload, missing file, generated or
# vendored path, binary content, or no added lines.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES="$HERE/rules.txt"

FILE="$(bash "$HERE/lib/payload.sh")"
[ -n "$FILE" ] || exit 0
[ -f "$FILE" ] || exit 0

case "$FILE" in
    */vendor/*|*/node_modules/*|*/public/build/*|*/public/themes/*/build/*|*/dist/*|*/storage/*|*/.git/*) exit 0 ;;
esac

GREP=grep
if ! grep -qP 'x' <<<'x' 2>/dev/null; then
    if command -v ggrep >/dev/null 2>&1 && ggrep -qP 'x' <<<'x' 2>/dev/null; then
        GREP=ggrep
    else
        echo "grep-gate: this grep has no -P support, so the PCRE rule table cannot run and nothing was checked. Install GNU grep and retry." >&2
        exit 1
    fi
fi

FINDINGS=""

record() {
    FINDINGS="${FINDINGS}${1}: ${2}"$'\n'
    [ -n "${3:-}" ] || return 0
    FINDINGS="${FINDINGS}$(printf '%s\n' "$3" | sed 's/^[[:space:]]*/      /')"$'\n'
}

tracked() {
    local dir
    dir="$(cd "$(dirname "$1")" 2>/dev/null && pwd)"
    [ -n "$dir" ] || return 1
    git -C "$dir" ls-files --error-unmatch -- "$1" >/dev/null 2>&1
}

case "$FILE" in
    */Resources/assets/css/app.css|*/resources/css/app.css) ;;
    *.css|*.scss|*.less)
        tracked "$FILE" || record NEW_CSS_FILE \
            "New stylesheets bypass the token system, and a .scss or .less file adds a build step this project does not run. Delete it and use Tailwind utility classes, or extend the tokens in packages/Webkul/Admin/src/Resources/assets/css/app.css."
        ;;
esac

ADDED="$(bash "$HERE/lib/added-lines.sh" "$FILE")"

if [ -n "$ADDED" ] && [ -r "$RULES" ]; then
    while IFS='~' read -r id path_re content_re message || [ -n "${id:-}" ]; do
        case "${id:-}" in ''|'#'*) continue ;; esac
        [ -n "${path_re:-}" ] && [ -n "${content_re:-}" ] || continue
        "$GREP" -qP -- "$path_re" <<<"$FILE" || continue
        hits="$("$GREP" -P -- "$content_re" <<<"$ADDED" | head -3 | cut -c1-160)"
        [ -n "$hits" ] || continue
        record "$id" "${message:-see skills/unopim-standards}" "$hits"
    done < "$RULES"
fi

if [ -n "$FINDINGS" ]; then
    {
        printf 'grep-gate BLOCKED %s\n\n' "$FILE"
        printf '%s' "$FINDINGS"
        printf '\nThese rules apply to the lines this edit added; pre-existing violations elsewhere are not your problem.\n'
        printf 'Fix only what you just wrote, then retry. See skills/unopim-standards and\n'
        printf 'skills/unopim-plugin-development/admin-ui.md.\n'
    } >&2
    exit 2
fi

exit 0
