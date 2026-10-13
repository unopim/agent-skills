# Assertions for skills/unopim-exec/detect-env.sh and skills/unopim-verify/verify.sh.
# Sourced by run-tests.sh, which provides REPO_ROOT and the assert_* helpers.

DETECT="$REPO_ROOT/skills/unopim-exec/detect-env.sh"
VERIFY="$REPO_ROOT/skills/unopim-verify/verify.sh"
HOOKS_TMP="$(mktemp -d)"

assert_passes "$DETECT" "$REPO_ROOT"
assert_output_contains "WRAPPER=" "$DETECT" "$REPO_ROOT"
assert_output_contains "APP_URL=" "$DETECT" "$REPO_ROOT"
assert_output_contains "DB_OVERRIDE=" "$DETECT" "$REPO_ROOT"
assert_output_contains "ES_OVERRIDE=" "$DETECT" "$REPO_ROOT"
assert_output_contains "PEST_ENV=" "$DETECT" "$REPO_ROOT"

assert_passes bash -c '[ "$("$1" "$2" | grep -c "")" -eq 5 ]' _ "$DETECT" "$REPO_ROOT"
assert_passes bash -c 'out="$("$1" "$2")"; ! printf "%s\n" "$out" | grep -qvE "^[A-Z_]+="' \
    _ "$DETECT" "$REPO_ROOT"

mkdir -p "$HOOKS_TMP/no-env"
assert_passes bash -c '[ "$("$1" "$2" | grep -c "")" -eq 5 ]' _ "$DETECT" "$HOOKS_TMP/no-env"
assert_passes bash -c '"$1" "$2" | grep -qx "APP_URL="' _ "$DETECT" "$HOOKS_TMP/no-env"

mkdir -p "$HOOKS_TMP/container-env"
printf 'APP_URL="http://example.test:8080"\nDB_HOST=db.invalid\nDB_PORT=3306\nELASTICSEARCH_ENABLED=true\nELASTICSEARCH_HOST=es.invalid:9200\n' \
    > "$HOOKS_TMP/container-env/.env"
assert_output_contains "APP_URL=http://example.test:8080" "$DETECT" "$HOOKS_TMP/container-env"
assert_output_contains "DB_OVERRIDE=DB_HOST=127.0.0.1" "$DETECT" "$HOOKS_TMP/container-env"
assert_output_contains "ES_OVERRIDE=ELASTICSEARCH_ENABLED=false" "$DETECT" "$HOOKS_TMP/container-env"
assert_output_contains "PEST_ENV=DB_HOST=127.0.0.1 ELASTICSEARCH_ENABLED=false" \
    "$DETECT" "$HOOKS_TMP/container-env"

mkdir -p "$HOOKS_TMP/host-env"
printf 'APP_URL=http://127.0.0.1:8000\nDB_HOST=127.0.0.1\nELASTICSEARCH_ENABLED=true\nELASTICSEARCH_HOST=127.0.0.1:9200\n' \
    > "$HOOKS_TMP/host-env/.env"
assert_passes bash -c '"$1" "$2" | grep -qx "DB_OVERRIDE="' _ "$DETECT" "$HOOKS_TMP/host-env"
assert_passes bash -c '"$1" "$2" | grep -qx "ES_OVERRIDE="' _ "$DETECT" "$HOOKS_TMP/host-env"
assert_passes bash -c '"$1" "$2" | grep -qx "PEST_ENV="' _ "$DETECT" "$HOOKS_TMP/host-env"

mkdir -p "$HOOKS_TMP/repeated-key"
awk 'BEGIN { for (i = 0; i < 5000; i++) print "APP_URL=http://example.test:8080/path/" i }' \
    > "$HOOKS_TMP/repeated-key/.env"
assert_passes "$DETECT" "$HOOKS_TMP/repeated-key"
assert_passes bash -c '[ "$("$1" "$2" | grep -c "")" -eq 5 ]' _ "$DETECT" "$HOOKS_TMP/repeated-key"
assert_output_contains "APP_URL=http://example.test:8080/path/0" "$DETECT" "$HOOKS_TMP/repeated-key"

mkdir -p "$HOOKS_TMP/es-off"
printf 'DB_HOST=127.0.0.1\nELASTICSEARCH_ENABLED=false\nELASTICSEARCH_HOST=es.invalid:9200\n' \
    > "$HOOKS_TMP/es-off/.env"
assert_passes bash -c '"$1" "$2" | grep -qx "ES_OVERRIDE="' _ "$DETECT" "$HOOKS_TMP/es-off"

mkdir -p "$HOOKS_TMP/containerized" "$HOOKS_TMP/no-php-bin"
for tool in bash sed head tr awk python3; do
    ln -sf "$(command -v "$tool")" "$HOOKS_TMP/no-php-bin/$tool"
done
printf 'x-app-env: &app-env\n  DB_HOST: "unopim-pgsql"\n\nservices:\n  unopim-pgsql:\n    image: postgres\n  unopim-fpm:\n    image: unopim\n  unopim-nginx:\n    image: nginx\n\nvolumes:\n  unopim-app:\n' \
    > "$HOOKS_TMP/containerized/docker-compose.yml"
assert_output_contains "WRAPPER=docker compose exec -T unopim-fpm php" \
    env PATH="$HOOKS_TMP/no-php-bin" "$DETECT" "$HOOKS_TMP/containerized"
assert_passes bash -c 'PATH="$3" "$1" "$2" | grep -qx "WRAPPER=php"' \
    _ "$DETECT" "$HOOKS_TMP/no-env" "$HOOKS_TMP/no-php-bin"

assert_fails "$VERIFY"
assert_output_contains "usage:" "$VERIFY"
assert_fails "$VERIFY" "$HOOKS_TMP/does-not-exist"

mkdir -p "$HOOKS_TMP/clean-project"
assert_passes "$VERIFY" "$HOOKS_TMP/clean-project" --changed "README.md"
assert_passes bash -c 'grep -qxE "[0-9]+" "$1/.verify-stamp" && [ "$(grep -c "" "$1/.verify-stamp")" -eq 1 ]' \
    _ "$HOOKS_TMP/clean-project"
for gate in pint pest larastan rector playwright translations; do
    assert_output_contains "$gate: SKIP" "$VERIFY" "$HOOKS_TMP/clean-project" --changed "README.md"
done
assert_output_contains "changed paths: 1" \
    "$VERIFY" "$HOOKS_TMP/clean-project" --changed "release notes.md"

mkdir -p "$HOOKS_TMP/php-project"
assert_fails "$VERIFY" "$HOOKS_TMP/php-project" --changed "src/Foo.php"
assert_output_contains "pint: FAIL" "$VERIFY" "$HOOKS_TMP/php-project" --changed "src/Foo.php"
assert_output_contains "vendor/bin/pint" "$VERIFY" "$HOOKS_TMP/php-project" --changed "src/Foo.php"
assert_output_contains "playwright: SKIP" "$VERIFY" "$HOOKS_TMP/php-project" --changed "src/Foo.php"
assert_passes bash -c '! [ -e "$1/.verify-stamp" ]' _ "$HOOKS_TMP/php-project"

mkdir -p "$HOOKS_TMP/relative/project"
assert_passes bash -c 'cd "$1" && "$2" project --changed README.md >/dev/null 2>&1 \
    && [ -f "$1/project/.verify-stamp" ]' _ "$HOOKS_TMP/relative" "$VERIFY"

mkdir -p "$HOOKS_TMP/readonly"
chmod 500 "$HOOKS_TMP/readonly"
assert_fails "$VERIFY" "$HOOKS_TMP/readonly" --changed "README.md"
assert_output_contains ".verify-stamp" "$VERIFY" "$HOOKS_TMP/readonly" --changed "README.md"
chmod 700 "$HOOKS_TMP/readonly"

STUBBED="$HOOKS_TMP/stubbed"
mkdir -p "$STUBBED/vendor/bin" "$HOOKS_TMP/stub-bin"
printf 'APP_URL=http://example.test:8080\nDB_HOST=db.invalid\n' > "$STUBBED/.env"
: > "$STUBBED/composer.json"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUBBED/vendor/bin/pint"
printf '#!/usr/bin/env bash\nprintf %%s "${DB_HOST:-unset}" > pest-env.txt\n' > "$STUBBED/vendor/bin/pest"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUBBED/vendor/bin/phpstan"
printf '#!/usr/bin/env bash\nexit 1\n' > "$HOOKS_TMP/stub-bin/composer"
printf '#!/usr/bin/env bash\nprintf %%s "${BASE_URL:-unset}" > ../../pw-env.txt\n' \
    > "$HOOKS_TMP/stub-bin/npx"
printf '#!/usr/bin/env bash\nexit 0\n' > "$HOOKS_TMP/stub-bin/php"
chmod +x "$STUBBED/vendor/bin/pint" "$STUBBED/vendor/bin/pest" \
    "$STUBBED/vendor/bin/phpstan" "$HOOKS_TMP/stub-bin/composer" \
    "$HOOKS_TMP/stub-bin/npx" "$HOOKS_TMP/stub-bin/php"

assert_passes env PATH="$HOOKS_TMP/stub-bin:$PATH" "$VERIFY" "$STUBBED" --changed "src/Foo.php"
assert_output_contains "pest: PASS" \
    env PATH="$HOOKS_TMP/stub-bin:$PATH" "$VERIFY" "$STUBBED" --changed "src/Foo.php"
assert_output_contains "rector: ADVISORY-FAIL" \
    env PATH="$HOOKS_TMP/stub-bin:$PATH" "$VERIFY" "$STUBBED" --changed "src/Foo.php"
assert_passes bash -c 'grep -qx "127.0.0.1" "$1/pest-env.txt"' _ "$STUBBED"
assert_passes bash -c 'grep -qxE "[0-9]+" "$1/.verify-stamp"' _ "$STUBBED"

printf '#!/usr/bin/env bash\nexit 1\n' > "$STUBBED/vendor/bin/pest"
rm -f "$STUBBED/.verify-stamp"
assert_fails env PATH="$HOOKS_TMP/stub-bin:$PATH" "$VERIFY" "$STUBBED" --changed "src/Foo.php"
assert_passes bash -c '! [ -e "$1/.verify-stamp" ]' _ "$STUBBED"

mkdir -p "$STUBBED/tests/e2e-pw"
: > "$STUBBED/artisan"
assert_output_contains "translations: PASS" \
    env PATH="$HOOKS_TMP/stub-bin:$PATH" "$VERIFY" "$STUBBED" \
    --changed "packages/Webkul/Admin/src/Resources/lang/en_US/app.php"
assert_output_contains "playwright: PASS" \
    env PATH="$HOOKS_TMP/stub-bin:$PATH" "$VERIFY" "$STUBBED" \
    --changed "packages/Webkul/Admin/src/Resources/views/index.blade.php"
assert_passes bash -c 'grep -qx "http://example.test:8080" "$1/pw-env.txt"' _ "$STUBBED"

rm -rf "$HOOKS_TMP"
unset DETECT VERIFY HOOKS_TMP STUBBED gate

# A Stop with no baseline cannot tell the session's work from the branch's, so
# it must seed the baseline and pass rather than blame the whole tree.
SWEEP="$REPO_ROOT/hooks/sweep-gate.sh"
SWEEP_REPO="$(mktemp -d)"
SWEEP_STATE="${TMPDIR:-/tmp}/unopim-sweep-sweepbaseline-"
rm -f "$SWEEP_STATE"* 2>/dev/null

git -C "$SWEEP_REPO" init -q
git -C "$SWEEP_REPO" config user.email t@t.t
git -C "$SWEEP_REPO" config user.name t
mkdir -p "$SWEEP_REPO/packages/Webkul/Foo/src/Resources/views"
printf 'seed\n' > "$SWEEP_REPO/seed.txt"
git -C "$SWEEP_REPO" add -A
git -C "$SWEEP_REPO" commit -qm seed
printf '<div class="fixed inset-0">\n<input type="text" name="x">\n</div>\n' \
    > "$SWEEP_REPO/packages/Webkul/Foo/src/Resources/views/edit.blade.php"

sweep_stop() {
    printf '{"session_id":"sweepbaseline","stop_hook_active":false}' \
        | env CLAUDE_PROJECT_DIR="$SWEEP_REPO" "$SWEEP"
}

assert_passes sweep_stop
assert_passes bash -c 'ls "$1"* >/dev/null 2>&1' _ "$SWEEP_STATE"

printf '<div class="bg-purple-600">x</div>\n' \
    >> "$SWEEP_REPO/packages/Webkul/Foo/src/Resources/views/edit.blade.php"
assert_fails sweep_stop
assert_output_contains "TAILWIND_INTENT" sweep_stop

rm -rf "$SWEEP_REPO"
rm -f "$SWEEP_STATE"* 2>/dev/null
unset SWEEP SWEEP_REPO SWEEP_STATE

# verify-gate must not demand verification for a branch that arrived dirty:
# without a baseline it cannot tell the session's work from the branch's.
VG="$REPO_ROOT/hooks/verify-gate.sh"
VG_REPO="$(mktemp -d)"
VG_STATE="${TMPDIR:-/tmp}/unopim-verify-verifybaseline-"
rm -f "$VG_STATE"* 2>/dev/null

git -C "$VG_REPO" init -q
git -C "$VG_REPO" config user.email t@t.t
git -C "$VG_REPO" config user.name t
mkdir -p "$VG_REPO/src"
printf 'seed\n' > "$VG_REPO/seed.txt"
git -C "$VG_REPO" add -A
git -C "$VG_REPO" commit -qm seed
printf '<?php\n' > "$VG_REPO/src/Old.php"

vg_stop() {
    printf '{"session_id":"verifybaseline","stop_hook_active":false}' \
        | env CLAUDE_PROJECT_DIR="$VG_REPO" "$VG"
}

assert_passes vg_stop
assert_passes vg_stop
assert_passes bash -c 'ls "$1"* >/dev/null 2>&1' _ "$VG_STATE"

sleep 1
printf '<?php\n' > "$VG_REPO/src/New.php"
assert_fails vg_stop
assert_output_contains "src/New.php" vg_stop

rm -rf "$VG_REPO"
rm -f "$VG_STATE"* 2>/dev/null
unset VG VG_REPO VG_STATE

