#!/usr/bin/env bash
# Runs the six UnoPim completion gates against a checkout, in the order
# unopim-verify documents: pint, pest, larastan, rector, playwright, translations.
# Usage: verify.sh PROJECT_ROOT [--changed FILE...]
# With no --changed list every gate applies; with one, a gate runs only when a
# changed path matches it. Rector is advisory: reported, never fatal, because a
# repo-wide dry run reports pre-existing debt this change did not add.
# Exits 0 only when every applicable gate passed, and then writes
# PROJECT_ROOT/.verify-stamp holding one integer, the unix time of the pass.
# hooks/verify-gate.sh reads that stamp, so its format is a contract.
set -uo pipefail

usage() {
    echo "usage: verify.sh PROJECT_ROOT [--changed FILE...]" >&2
}

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

case "$1" in
    -h|--help|--changed) usage; exit 1 ;;
esac

ROOT="$1"; shift
CHANGED=()
if [ $# -gt 0 ]; then
    if [ "$1" != "--changed" ]; then
        usage
        exit 1
    fi
    shift
    CHANGED=("$@")
fi

if [ ! -d "$ROOT" ]; then
    echo "verify: not a directory: $ROOT" >&2
    exit 1
fi
ROOT="$(cd "$ROOT" && pwd)" || exit 1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="$HERE/../unopim-exec/detect-env.sh"

WRAPPER="php"
APP_URL=""
PEST_ENV=""
if [ -x "$DETECT" ]; then
    while IFS='=' read -r key value; do
        case "$key" in
            WRAPPER)  WRAPPER="$value" ;;
            APP_URL)  APP_URL="$value" ;;
            PEST_ENV) PEST_ENV="$value" ;;
        esac
    done < <("$DETECT" "$ROOT")
else
    echo "verify: unopim-exec/detect-env.sh missing, assuming host php and no overrides" >&2
fi

[ -n "$WRAPPER" ] || WRAPPER="php"
read -r -a WRAP <<< "$WRAPPER"
read -r -a OVERRIDES <<< "$PEST_ENV"

cd "$ROOT" || exit 1

STATUS=0
SUMMARY=()

record() {
    SUMMARY+=("$1: $2")
}

touches() {
    if [ "${#CHANGED[@]}" -eq 0 ]; then
        return 0
    fi
    printf '%s\n' "${CHANGED[@]}" | grep -qE "$1"
}

skip() {
    printf '\n== %s\n   skipped: %s\n' "$1" "$2"
    record "$1" SKIP
}

missing() {
    printf '\n== %s\n   cannot run: %s\n' "$1" "$2" >&2
    record "$1" FAIL
    STATUS=1
}

run_gate() {
    local name="$1"; shift
    printf '\n== %s\n' "$name"
    if "$@"; then
        record "$name" PASS
        return 0
    fi
    record "$name" FAIL
    STATUS=1
    return 1
}

run_advisory() {
    local name="$1"; shift
    printf '\n== %s (advisory)\n' "$name"
    if "$@"; then
        record "$name" PASS
        return 0
    fi
    record "$name" "ADVISORY-FAIL"
    printf '   %s reported work to do; it does not fail this run, fix it before merge\n' "$name"
    return 0
}

pint_gate() {
    vendor/bin/pint --dirty && vendor/bin/pint --test --dirty
}

pest_gate() {
    env ${OVERRIDES[@]+"${OVERRIDES[@]}"} vendor/bin/pest
}

larastan_gate() {
    vendor/bin/phpstan analyse --memory-limit=2G
}

rector_gate() {
    composer rector-dry
}

playwright_gate() {
    (cd tests/e2e-pw && env BASE_URL="$APP_URL" npx playwright test)
}

translations_gate() {
    "${WRAP[@]}" artisan unopim:translations:check
}

PHP_RE='\.php$'
VIEW_RE='(\.blade\.php$|\.vue$|\.js$|/lang/|Resources/lang/)'
LANG_RE='(/lang/|Resources/lang/|\.blade\.php$|\.vue$|\.js$)'

if [ "${#CHANGED[@]}" -eq 0 ]; then
    echo "verify: no --changed list, every gate applies"
else
    printf 'verify: changed paths: %s\n' "${#CHANGED[@]}"
fi

if touches "$PHP_RE"; then
    if [ -x vendor/bin/pint ]; then
        run_gate pint pint_gate
    else
        missing pint "vendor/bin/pint not found — run composer install"
    fi
else
    skip pint "no PHP change"
fi

if touches "$PHP_RE"; then
    if [ -x vendor/bin/pest ]; then
        run_gate pest pest_gate
    else
        missing pest "vendor/bin/pest not found — run composer install"
    fi
else
    skip pest "no PHP change"
fi

if touches "$PHP_RE"; then
    if [ -x vendor/bin/phpstan ]; then
        run_gate larastan larastan_gate
    else
        missing larastan "vendor/bin/phpstan not found — run composer install"
    fi
else
    skip larastan "no PHP change"
fi

if touches "$PHP_RE"; then
    if command -v composer >/dev/null 2>&1 && [ -f composer.json ]; then
        run_advisory rector rector_gate
    else
        skip rector "composer or composer.json unavailable"
    fi
else
    skip rector "no PHP change"
fi

if touches "$VIEW_RE"; then
    if [ -d tests/e2e-pw ]; then
        run_gate playwright playwright_gate
    else
        skip playwright "tests/e2e-pw absent in this checkout"
    fi
else
    skip playwright "no view, JS or translation change"
fi

if touches "$LANG_RE"; then
    if [ -f artisan ]; then
        run_gate translations translations_gate
    else
        missing translations "artisan not found — is this an UnoPim root?"
    fi
else
    skip translations "no view, JS or translation change"
fi

printf '\n== summary\n'
printf '   %s\n' "${SUMMARY[@]}"

if [ "$STATUS" -eq 0 ]; then
    if date -u +%s > "$ROOT/.verify-stamp"; then
        echo "verification passed"
    else
        echo "verify: gates passed but $ROOT/.verify-stamp is not writable" >&2
        STATUS=1
    fi
else
    echo "verification FAILED — fix the root cause, never suppress a gate" >&2
fi

exit "$STATUS"
