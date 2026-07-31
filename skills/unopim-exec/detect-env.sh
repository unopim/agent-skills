#!/usr/bin/env bash
# Resolves how shell commands must be run against an UnoPim checkout.
# Usage: detect-env.sh [PROJECT_ROOT]   (default: current directory)
# Contract: prints exactly five KEY=VALUE lines on stdout, in this order —
# WRAPPER, APP_URL, DB_OVERRIDE, ES_OVERRIDE, PEST_ENV — and nothing else.
# Exits 0 even when the checkout has no .env. Parsed by unopim-verify/verify.sh
# and by hooks/session-card.sh, so the line format is a contract.
set -euo pipefail

ROOT="${1:-$PWD}"
ENV_FILE="$ROOT/.env"

env_value() {
    [ -f "$ENV_FILE" ] || return 0
    awk -v key="$1" -v quote="'" '
        $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            sub("^[[:space:]]*" key "[[:space:]]*=", "")
            gsub(/\r/, "")
            sub(/^[[:space:]]+/, "")
            sub(/[[:space:]]+$/, "")
            first = substr($0, 1, 1)
            last = substr($0, length($0), 1)
            if (length($0) > 1 && first == last && (first == "\"" || first == quote)) {
                $0 = substr($0, 2, length($0) - 2)
            }
            print
            exit
        }
    ' "$ENV_FILE"
}

host_only() {
    printf '%s' "$1" \
        | sed -e 's#^[A-Za-z][A-Za-z0-9+.-]*://##' -e 's#/.*$##' -e 's#:[0-9]*$##'
}

resolves() {
    local host="$1"
    [ -n "$host" ] || return 1
    case "$host" in
        127.0.0.1|::1|0.0.0.0|localhost) return 0 ;;
    esac
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import socket,sys; socket.getaddrinfo(sys.argv[1], None)' "$host" \
            >/dev/null 2>&1
        return
    fi
    if command -v getent >/dev/null 2>&1; then
        getent hosts "$host" >/dev/null 2>&1
        return
    fi
    return 0
}

compose_file() {
    local candidate
    for candidate in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
        if [ -f "$ROOT/$candidate" ]; then
            printf '%s' "$ROOT/$candidate"
            return 0
        fi
    done
    return 1
}

app_service() {
    awk '
        /^[^[:space:]#]/ { in_services = ($0 ~ /^services:/); next }
        in_services && /^  [A-Za-z0-9._-]+:[[:space:]]*$/ {
            name = $1
            sub(/:$/, "", name)
            if (name ~ /(php|fpm|app|web)/) { print name; exit }
        }
    ' "$1"
}

# A running container outranks a host binary: a machine can have both, and the
# host php then has the wrong extensions and no route to the compose network.
WRAPPER="php"
if COMPOSE="$(compose_file)"; then
    SERVICE="$(app_service "$COMPOSE")"
    [ -n "$SERVICE" ] || SERVICE="app"
    # The wrapper is word-split by its consumers, so it stays free of paths.
    if command -v docker >/dev/null 2>&1 \
        && [ -n "$(docker compose -f "$COMPOSE" ps -q "$SERVICE" 2>/dev/null)" ]; then
        WRAPPER="docker compose exec -T $SERVICE php"
    elif ! command -v php >/dev/null 2>&1; then
        WRAPPER="docker compose exec -T $SERVICE php"
    fi
fi

APP_URL="$(env_value APP_URL)"
DB_HOST="$(host_only "$(env_value DB_HOST)")"
ES_HOST="$(host_only "$(env_value ELASTICSEARCH_HOST)")"
ES_ENABLED="$(env_value ELASTICSEARCH_ENABLED)"

DB_OVERRIDE=""
if [ -n "$DB_HOST" ] && ! resolves "$DB_HOST"; then
    DB_OVERRIDE="DB_HOST=127.0.0.1"
fi

ES_OVERRIDE=""
case "$(printf '%s' "$ES_ENABLED" | tr '[:upper:]' '[:lower:]')" in
    false|0|off|no) ;;
    *)
        if [ -n "$ES_HOST" ] && ! resolves "$ES_HOST"; then
            ES_OVERRIDE="ELASTICSEARCH_ENABLED=false"
        fi
        ;;
esac

PEST_ENV="$(printf '%s %s' "$DB_OVERRIDE" "$ES_OVERRIDE" | sed -e 's/^ *//' -e 's/ *$//')"

printf 'WRAPPER=%s\n' "$WRAPPER"
printf 'APP_URL=%s\n' "$APP_URL"
printf 'DB_OVERRIDE=%s\n' "$DB_OVERRIDE"
printf 'ES_OVERRIDE=%s\n' "$ES_OVERRIDE"
printf 'PEST_ENV=%s\n' "$PEST_ENV"
