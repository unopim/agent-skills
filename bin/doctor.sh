#!/usr/bin/env bash
#
# Check that an UnoPim checkout and this machine's Claude Code carry the AI tooling
# the skills assume.
#
# Usage:
#   bin/doctor.sh [UNOPIM_ROOT] [--fix] [--quiet]
#
# Required (exit 1 when missing):
#   laravel/boost      in composer.lock
#   Boost MCP server   an .mcp.json entry that runs `artisan boost:mcp`
# Recommended (warn only):
#   superpowers, laravel-boost and code-review Claude Code plugins, and a
#   Playwright MCP server for driving the admin UI.
#
# --fix installs what can be installed without a human: Boost through composer
# and `boost:install`, run through the php wrapper unopim-exec detects. Plugins
# are never installed for the user; the fix line says how.
# --quiet prints one line per gap and nothing when all is well, for the session card.
#
# Claude Code's user config is read from $CLAUDE_CONFIG_DIR, defaulting to ~/.claude.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT=""
FIX=0
QUIET=0

while [ $# -gt 0 ]; do
    case "$1" in
        --fix)     FIX=1 ;;
        --quiet)   QUIET=1 ;;
        -h|--help) sed -n '3,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)        printf 'doctor.sh: unknown option %s\n' "$1" >&2; exit 2 ;;
        *)         ROOT="$1" ;;
    esac
    shift
done

ROOT="${ROOT:-${CLAUDE_PROJECT_DIR:-$PWD}}"
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || { printf 'doctor.sh: no such directory\n' >&2; exit 2; }

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    USER_JSON="$CLAUDE_CONFIG_DIR/.claude.json"
else
    USER_JSON="$HOME/.claude.json"
fi

is_unopim() {
    [ -f "$ROOT/artisan" ] && { [ -d "$ROOT/packages/Webkul" ] || grep -qi unopim "$ROOT/composer.json" 2>/dev/null; }
}

php_wrapper() {
    local detect="$HERE/skills/unopim-exec/detect-env.sh"
    [ -f "$detect" ] || detect="$(dirname "${BASH_SOURCE[0]}")/detect-env.sh"
    [ -f "$detect" ] || { printf 'php'; return; }
    local wrapper
    wrapper="$(bash "$detect" "$ROOT" 2>/dev/null | sed -n 's/^WRAPPER=//p' | head -1)"
    printf '%s' "${wrapper:-php}"
}

json_probe() {
    python3 - "$@" <<'PY' 2>/dev/null
import json, sys

kind, root, config_dir, user_json = sys.argv[1:5]

def load(path):
    try:
        with open(path) as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return {}

def servers():
    found = dict(load(root + "/.mcp.json").get("mcpServers") or {})
    user = load(user_json)
    found.update(user.get("mcpServers") or {})
    found.update(((user.get("projects") or {}).get(root) or {}).get("mcpServers") or {})
    return found

def plugins():
    data = load(config_dir + "/plugins/installed_plugins.json")
    return list((data.get("plugins") or {}).keys())

def mentions(name, server, needle):
    text = name + " " + json.dumps(server)
    return needle in text

if kind == "boost-package":
    lock = load(root + "/composer.lock")
    names = [p.get("name") for p in (lock.get("packages") or []) + (lock.get("packages-dev") or [])]
    sys.exit(0 if "laravel/boost" in names else 1)

if kind == "boost-mcp":
    sys.exit(0 if any(mentions(n, s, "boost:mcp") for n, s in servers().items()) else 1)

if kind == "boost-mcp-command":
    for name, server in servers().items():
        if mentions(name, server, "boost:mcp"):
            print(server.get("command", ""))
            break
    sys.exit(0)

if kind == "playwright":
    if any(p.startswith("playwright@") for p in plugins()):
        sys.exit(0)
    sys.exit(0 if any(mentions(n, s, "playwright") for n, s in servers().items()) else 1)

if kind == "plugin":
    wanted = sys.argv[5]
    sys.exit(0 if any(p.startswith(wanted + "@") for p in plugins()) else 1)

sys.exit(2)
PY
}

probe() { json_probe "$1" "$ROOT" "$CONFIG_DIR" "$USER_JSON" "${2:-}"; }

REQUIRED_GAPS=0
LINES=()

report() {
    local level="$1" what="$2" fix="$3"
    if [ "$QUIET" -eq 1 ]; then
        LINES+=("$level $what — $fix")
    else
        LINES+=("  [$level] $what"$'\n'"            fix: $fix")
    fi
    [ "$level" = "MISSING" ] && REQUIRED_GAPS=$((REQUIRED_GAPS + 1))
    return 0
}

if ! command -v python3 >/dev/null 2>&1; then
    printf 'doctor.sh: python3 is needed to read composer.lock and the MCP config\n' >&2
    exit 2
fi

if [ "$FIX" -eq 1 ]; then
    if ! is_unopim; then
        printf 'doctor.sh: %s is not an UnoPim checkout; --fix changes nothing outside one\n' "$ROOT" >&2
        exit 2
    fi
    PHP="$(php_wrapper)"
    COMPOSER="${PHP%php}composer"
    if ! probe boost-package; then
        printf 'installing laravel/boost …\n'
        if grep -q '"laravel/boost"' "$ROOT/composer.json" 2>/dev/null; then
            (cd "$ROOT" && $COMPOSER install --no-interaction) || true
        else
            (cd "$ROOT" && $COMPOSER require --dev laravel/boost --no-interaction) || true
        fi
    fi
    if probe boost-package && ! probe boost-mcp; then
        printf 'configuring the Boost MCP server, guidelines and skills …\n'
        (cd "$ROOT" && $PHP artisan boost:install --mcp --guidelines --skills --no-interaction) || true
    fi
fi

PHP="$(php_wrapper)"

if ! probe boost-package; then
    report MISSING "laravel/boost is not installed" "composer require --dev laravel/boost  (or: bin/doctor.sh --fix)"
fi

if ! probe boost-mcp; then
    report MISSING "Laravel Boost MCP server is not configured (.mcp.json)" "$PHP artisan boost:install --mcp --guidelines --skills  (or: bin/doctor.sh --fix)"
elif [ "$PHP" != "php" ] && [ "$(probe boost-mcp-command)" = "php" ]; then
    report WARN "Boost MCP runs host php but this workspace serves from a container" "point the laravel-boost entry in .mcp.json at: $PHP artisan boost:mcp"
fi

if ! probe plugin superpowers; then
    report WARN "superpowers plugin is not installed" "/plugin install superpowers@claude-plugins-official"
fi
if ! probe plugin laravel-boost; then
    report WARN "laravel-boost plugin is not installed" "/plugin install laravel-boost@claude-plugins-official"
fi
if ! probe plugin code-review; then
    report WARN "code-review plugin is not installed" "/plugin install code-review@claude-plugins-official"
fi
if ! probe playwright; then
    report WARN "no Playwright MCP server for driving the admin UI" "claude mcp add playwright -- npx -y @playwright/mcp@latest"
fi

if [ "$QUIET" -eq 1 ]; then
    [ "${#LINES[@]}" -gt 0 ] && printf '%s\n' "${LINES[@]}"
else
    printf 'UnoPim AI tooling — %s\n' "$ROOT"
    if [ "${#LINES[@]}" -eq 0 ]; then
        printf '  [OK] Laravel Boost, its MCP server, superpowers, laravel-boost, code-review and Playwright MCP\n'
    else
        printf '%s\n' "${LINES[@]}"
    fi
fi

[ "$REQUIRED_GAPS" -eq 0 ]
