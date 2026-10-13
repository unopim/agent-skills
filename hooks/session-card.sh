#!/usr/bin/env bash
# SessionStart card: prints how this workspace is served and how to run
# commands against it, from unopim-exec's detection. Never fails a session
# start — an absent detector degrades to a card with unknowns.
set -uo pipefail

ROOT="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DETECT="$HERE/detect-env.sh"
[ -f "$DETECT" ] || DETECT="$HERE/../skills/unopim-exec/detect-env.sh"

WRAPPER=""
APP_URL=""
PEST_ENV=""

if [ -f "$DETECT" ]; then
    while IFS='=' read -r key value; do
        case "$key" in
            WRAPPER) WRAPPER="$value" ;;
            APP_URL) APP_URL="$value" ;;
            PEST_ENV) PEST_ENV="$value" ;;
        esac
    done < <(bash "$DETECT" "$ROOT" 2>/dev/null)
fi

DOCTOR="$HERE/doctor.sh"
[ -f "$DOCTOR" ] || DOCTOR="$HERE/../bin/doctor.sh"
TOOLING=""
if [ -f "$DOCTOR" ]; then
    TOOLING="$(bash "$DOCTOR" "$ROOT" --quiet 2>/dev/null)"
fi

cat <<CARD
UnoPim workspace
  root         : $ROOT
  served at    : ${APP_URL:-unknown, read APP_URL from .env}
  php wrapper  : ${WRAPPER:-php}
  pest prefix  : ${PEST_ENV:-none needed}
  verify       : pint, pest, larastan, rector, playwright, translations
Standards are enforced at edit time; a block names the rule and the fix, and
judges only the lines an edit adds.
CARD

if [ -n "$TOOLING" ]; then
    printf 'AI tooling gaps (unopim-setup skill):\n'
    printf '%s\n' "$TOOLING" | sed 's/^/  /'
    if printf '%s\n' "$TOOLING" | grep -q '^MISSING'; then
        printf 'Laravel Boost is required. Run the MISSING fix, or %s --fix, before writing code.\n' "$DOCTOR"
    fi
fi

exit 0
