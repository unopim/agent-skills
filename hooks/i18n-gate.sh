#!/usr/bin/env bash
# PostToolUse gate for edits under Resources/lang/: runs
# unopim:translations:check and blocks with exit 2 when a locale is
# incomplete. Exits 0 when the checkout has no artisan, no php, or no such
# command — not every checkout is a full application.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD="$HERE/lib/payload.sh"
[ -f "$PAYLOAD" ] || exit 0

FILE="$(bash "$PAYLOAD" 2>/dev/null)"

case "$FILE" in
    *Resources/lang/*) ;;
    *) exit 0 ;;
esac

case "$FILE" in
    /*) ;;
    *) FILE="$PWD/$FILE" ;;
esac

ROOT="$(dirname "$FILE")"
while [ "$ROOT" != "/" ] && [ ! -f "$ROOT/artisan" ]; do
    ROOT="$(dirname "$ROOT")"
done
[ -f "$ROOT/artisan" ] || exit 0
command -v php >/dev/null 2>&1 || exit 0

OUT="$(cd "$ROOT" && php artisan unopim:translations:check 2>&1)"
STATUS=$?
[ "$STATUS" -eq 0 ] && exit 0

case "$OUT" in
    *"is not defined"*|*"There are no commands defined"*) exit 0 ;;
esac

{
    echo "i18n-gate: translations are incomplete."
    printf '%s\n' "$OUT" | tail -20
    echo
    echo "Add the key to en_US first, then propagate it to every locale with a"
    echo "value translated into that language. Keep :placeholders untranslated."
} >&2

exit 2
