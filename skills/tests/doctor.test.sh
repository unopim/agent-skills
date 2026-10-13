# Tests for bin/doctor.sh.
# Contract under test: Laravel Boost (package + MCP server entry) is required and
# a missing one exits 1 with the fix command; superpowers, the laravel-boost and
# code-review plugins and a Playwright MCP server are recommended and only warn;
# --quiet prints one line per gap and nothing when all is well; --fix never runs
# outside an UnoPim checkout. Claude's user config is redirected through
# CLAUDE_CONFIG_DIR so the developer's real plugins never decide a verdict.

DOCTOR="$REPO_ROOT/bin/doctor.sh"
DOC_TMP="$(mktemp -d "${TMPDIR:-/tmp}/unopim-doctor.XXXXXX")"

_doc_expect() {
    if [ "$2" -eq 0 ]; then
        echo "  ok   : $1"
    else
        echo "  FAIL : $1"
        FAILED=1
    fi
}

_doc_app() {
    local app="$DOC_TMP/$1"
    mkdir -p "$app/packages/Webkul"
    printf '<?php\n' > "$app/artisan"
    printf '%s' "$app"
}

_doc_with_boost() {
    printf '{"packages":[],"packages-dev":[{"name":"laravel/boost","version":"v2.7.0"}]}\n' > "$1/composer.lock"
    printf '{"mcpServers":{"laravel-boost":{"command":"php","args":["artisan","boost:mcp"]}}}\n' > "$1/.mcp.json"
}

_doc_config() {
    local cfg="$DOC_TMP/$1"
    mkdir -p "$cfg/plugins"
    printf '%s' "$cfg"
}

_doc_plugins() {
    printf '{"version":2,"plugins":{%s}}\n' "$2" > "$1/plugins/installed_plugins.json"
}

_doc_run() {
    local cfg="$1"; shift
    CLAUDE_CONFIG_DIR="$cfg" bash "$DOCTOR" "$@" </dev/null 2>&1
}

_doc_cfg_full="$(_doc_config full)"
_doc_plugins "$_doc_cfg_full" '"superpowers@claude-plugins-official":[{}],"laravel-boost@claude-plugins-official":[{}],"code-review@claude-plugins-official":[{}],"playwright@claude-plugins-official":[{}]'
_doc_cfg_none="$(_doc_config none)"
_doc_plugins "$_doc_cfg_none" ''

# A checkout with Boost wired and every plugin present passes cleanly
_doc_ok="$(_doc_app ok)"
_doc_with_boost "$_doc_ok"
_doc_out="$(_doc_run "$_doc_cfg_full" "$_doc_ok")"; _doc_status=$?
_doc_expect "complete setup exits 0" "$_doc_status"
printf '%s' "$_doc_out" | grep -q 'MISSING'
[ $? -ne 0 ]; _doc_expect "complete setup reports nothing missing" "$?"
_doc_out="$(_doc_run "$_doc_cfg_full" "$_doc_ok" --quiet)"
[ -z "$_doc_out" ]; _doc_expect "--quiet is silent when nothing is missing" "$?"

# Boost absent from composer.lock is required: exit 1 and name the fix
_doc_nopkg="$(_doc_app nopkg)"
printf '{"packages":[],"packages-dev":[]}\n' > "$_doc_nopkg/composer.lock"
_doc_out="$(_doc_run "$_doc_cfg_full" "$_doc_nopkg")"; _doc_status=$?
[ "$_doc_status" -eq 1 ]; _doc_expect "missing laravel/boost exits 1" "$?"
printf '%s' "$_doc_out" | grep -qF 'composer require --dev laravel/boost'
_doc_expect "missing laravel/boost names composer require" "$?"

# Package present but no MCP entry: still required, fix is boost:install
_doc_nomcp="$(_doc_app nomcp)"
_doc_with_boost "$_doc_nomcp"
rm -f "$_doc_nomcp/.mcp.json"
_doc_out="$(_doc_run "$_doc_cfg_full" "$_doc_nomcp")"; _doc_status=$?
[ "$_doc_status" -eq 1 ]; _doc_expect "missing Boost MCP entry exits 1" "$?"
printf '%s' "$_doc_out" | grep -qF 'boost:install --mcp --guidelines --skills'
_doc_expect "missing Boost MCP entry names boost:install" "$?"

# Recommended plugins absent only warn
_doc_out="$(_doc_run "$_doc_cfg_none" "$_doc_ok")"; _doc_status=$?
_doc_expect "missing recommended plugins still exits 0" "$_doc_status"
for _doc_want in 'superpowers@claude-plugins-official' 'laravel-boost@claude-plugins-official' 'code-review@claude-plugins-official' '@playwright/mcp'; do
    printf '%s' "$_doc_out" | grep -qF "$_doc_want"
    _doc_expect "missing recommendation names $_doc_want" "$?"
done

# A Playwright MCP server in .mcp.json satisfies the Playwright check
_doc_pw="$(_doc_app pw)"
_doc_with_boost "$_doc_pw"
printf '{"mcpServers":{"laravel-boost":{"command":"php","args":["artisan","boost:mcp"]},"playwright":{"command":"npx","args":["@playwright/mcp"]}}}\n' > "$_doc_pw/.mcp.json"
_doc_out="$(_doc_run "$_doc_cfg_none" "$_doc_pw")"
printf '%s' "$_doc_out" | grep -qF '@playwright/mcp@'
[ $? -ne 0 ]; _doc_expect "project Playwright MCP server satisfies the check" "$?"

# --quiet prints one line per gap
_doc_out="$(_doc_run "$_doc_cfg_none" "$_doc_nomcp" --quiet)"
_doc_lines="$(printf '%s\n' "$_doc_out" | grep -c .)"
[ "$_doc_lines" -eq 5 ]; _doc_expect "--quiet prints one line per gap (got $_doc_lines)" "$?"

# --fix refuses a directory that is not an UnoPim checkout
mkdir -p "$DOC_TMP/notapp"
_doc_out="$(_doc_run "$_doc_cfg_full" "$DOC_TMP/notapp" --fix)"; _doc_status=$?
[ "$_doc_status" -eq 2 ]; _doc_expect "--fix outside an UnoPim checkout exits 2" "$?"

# --fix installs Boost and wires its MCP server through the php wrapper; stub
# composer and php record the calls instead of touching the network
_doc_bin="$DOC_TMP/bin"
mkdir -p "$_doc_bin"
cat > "$_doc_bin/composer" <<'STUB'
#!/usr/bin/env bash
printf 'composer %s\n' "$*" >> calls.log
printf '{"packages":[],"packages-dev":[{"name":"laravel/boost"}]}\n' > composer.lock
STUB
cat > "$_doc_bin/php" <<'STUB'
#!/usr/bin/env bash
printf 'php %s\n' "$*" >> calls.log
printf '{"mcpServers":{"laravel-boost":{"command":"php","args":["artisan","boost:mcp"]}}}\n' > .mcp.json
STUB
chmod +x "$_doc_bin/composer" "$_doc_bin/php"
_doc_fix="$(_doc_app fix)"
printf '{"require-dev":{}}\n' > "$_doc_fix/composer.json"
_doc_out="$(PATH="$_doc_bin:$PATH" _doc_run "$_doc_cfg_full" "$_doc_fix" --fix)"; _doc_status=$?
_doc_expect "--fix leaves a passing setup" "$_doc_status"
grep -qF 'composer require --dev laravel/boost' "$_doc_fix/calls.log"
_doc_expect "--fix requires laravel/boost when composer.json lacks it" "$?"
grep -qF 'php artisan boost:install --mcp --guidelines --skills --no-interaction' "$_doc_fix/calls.log"
_doc_expect "--fix runs boost:install non-interactively" "$?"

rm -rf "$DOC_TMP"
