#!/usr/bin/env bash
# PostToolUse gate for *.php: runs Pint in fix mode on the edited file and
# reports only when it reformatted something. Non-blocking by contract — it
# always exits 0, including when a dependency or Pint itself is absent.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD="$HERE/lib/payload.sh"
[ -f "$PAYLOAD" ] || exit 0

FILE="$(bash "$PAYLOAD" 2>/dev/null)"

case "$FILE" in
    *.php) ;;
    *) exit 0 ;;
esac

case "$FILE" in
    /*) ;;
    *) FILE="$PWD/$FILE" ;;
esac
[ -f "$FILE" ] || exit 0

ROOT="$(dirname "$FILE")"
while [ "$ROOT" != "/" ] && [ ! -x "$ROOT/vendor/bin/pint" ]; do
    ROOT="$(dirname "$ROOT")"
done
[ -x "$ROOT/vendor/bin/pint" ] || exit 0

BEFORE="$(cksum < "$FILE")"
(cd "$ROOT" && ./vendor/bin/pint "$FILE" >/dev/null 2>&1)
AFTER="$(cksum < "$FILE")"

if [ "$BEFORE" != "$AFTER" ]; then
    echo "pint-gate: reformatted $FILE — re-read it before editing again."
fi

exit 0
